import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/pedido.dart';
import 'impressora_servico.dart';

const _selectPedido = '*, itens_pedido(*, itens_pedido_opcoes(*))';

/// Estado central do app: empresa, lista de pedidos, realtime e alertas
class PedidosServico extends ChangeNotifier {
  PedidosServico._();
  static final instancia = PedidosServico._();

  SupabaseClient get _db => Supabase.instance.client;

  EmpresaLojista? empresa;
  List<Pedido> pedidos = [];
  bool carregando = false;
  String? erro;
  bool conectadoTempoReal = false;

  /// {liberada, situacao, valida_ate, dias_restantes} — calculado no servidor
  Map<String, dynamic>? assinatura;
  bool get assinaturaLiberada => assinatura?['liberada'] != false;
  bool get emTeste => assinatura?['situacao'] == 'teste';
  int? get diasRestantes => assinatura?['dias_restantes'] as int?;
  int _ciclos = 0;

  RealtimeChannel? _canal;
  Timer? _intervalo;
  final _player = AudioPlayer();
  bool _tocando = false;
  final Set<int> _conhecidos = {};
  final Set<int> _jaImpressosAuto = {};
  bool _primeiraCarga = true;

  /// Chamado após login. Retorna false se o usuário não tem loja.
  Future<bool> iniciar() async {
    carregando = true;
    erro = null;
    notifyListeners();
    try {
      final vinculo = await _db.from('usuarios_empresa').select('id_empresa').order('id').limit(1).maybeSingle();
      if (vinculo == null) {
        carregando = false;
        notifyListeners();
        return false;
      }
      final dados = await _db
          .from('empresas')
          .select(camposEmpresa)
          .eq('id', vinculo['id_empresa'])
          .single();
      empresa = EmpresaLojista.fromJson(dados);
      await verificarAssinatura();
      await _player.setReleaseMode(ReleaseMode.loop);
      _primeiraCarga = true;
      await recarregar();
      _assinarTempoReal();
      _intervalo?.cancel();
      // reforço caso o realtime caia (rede do celular oscila)
      _intervalo = Timer.periodic(const Duration(seconds: 45), (_) {
        recarregar();
        // assinatura: confere a cada ~5 min
        if (++_ciclos % 7 == 0) verificarAssinatura();
      });
      return true;
    } catch (e) {
      erro = '$e';
      carregando = false;
      notifyListeners();
      return true;
    }
  }

  void _assinarTempoReal() {
    final idEmpresa = empresa!.id;
    if (_canal != null) _db.removeChannel(_canal!);
    _canal = _db
        .channel('pedidos-app-$idEmpresa')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id_empresa', value: idEmpresa),
          callback: (_) => recarregar(),
        )
        .subscribe((status, [_]) {
      conectadoTempoReal = status == RealtimeSubscribeStatus.subscribed;
      notifyListeners();
    });
  }

  Future<void> recarregar() async {
    if (empresa == null) return;
    try {
      final desde = DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String();
      final dados = await _db
          .from('pedidos')
          .select(_selectPedido)
          .eq('id_empresa', empresa!.id)
          .gte('criado_em', desde)
          .order('criado_em', ascending: false)
          .limit(200);
      pedidos = (dados as List).map((j) => Pedido.fromJson(j as Map<String, dynamic>)).toList();
      erro = null;

      final novos = pedidos.where((p) => p.statusPedido == 'novo' && !_conhecidos.contains(p.id)).toList();
      _conhecidos.addAll(pedidos.map((p) => p.id));
      if (!_primeiraCarga && novos.isNotEmpty) _aoChegarPedidos(novos);
      _primeiraCarga = false;
      _atualizarAlerta();
    } catch (e) {
      erro = 'Sem conexão com o servidor. Tentando novamente...';
    }
    carregando = false;
    notifyListeners();
  }

  void _aoChegarPedidos(List<Pedido> novos) {
    final imp = ImpressoraServico.instancia;
    if (imp.config.automatica == ImpressaoAutomatica.aoChegar && imp.configurada) {
      for (final p in novos) {
        _imprimirAuto(p);
      }
    }
  }

  /// Toca em loop enquanto houver pedido "novo" sem aceitar
  Future<void> _atualizarAlerta() async {
    final temNovo = assinaturaLiberada && pedidos.any((p) => p.statusPedido == 'novo');
    if (temNovo && !_tocando) {
      _tocando = true;
      await _player.play(AssetSource('sons/alerta.wav'), volume: 1);
    } else if (!temNovo && _tocando) {
      _tocando = false;
      await _player.stop();
    }
  }

  Future<void> silenciar() async {
    _tocando = false;
    await _player.stop();
  }

  Future<void> mudarStatus(Pedido p, String status) async {
    await _db.from('pedidos').update({'status_pedido': status}).eq('id', p.id);
    final imp = ImpressoraServico.instancia;
    if (status == 'aceito' && imp.config.automatica == ImpressaoAutomatica.aoAceitar && imp.configurada) {
      await _imprimirAuto(p);
    }
    await recarregar();
  }

  Future<void> _imprimirAuto(Pedido p) async {
    if (_jaImpressosAuto.contains(p.id)) return;
    _jaImpressosAuto.add(p.id);
    try {
      await imprimir(p);
    } catch (e) {
      erro = 'Falha ao imprimir pedido #${p.numeroPedido}: $e';
      notifyListeners();
    }
  }

  Future<void> imprimir(Pedido p) async {
    await ImpressoraServico.instancia.imprimirPedido(p, empresa?.nomeEmpresa ?? '');
    if (!p.impresso) {
      await _db.from('pedidos').update({'impresso': true}).eq('id', p.id);
    }
  }

  Future<void> alternarLoja() async {
    if (empresa == null) return;
    final nova = !empresa!.abertaManual;
    await _db.from('empresas').update({'aberta_manual': nova}).eq('id', empresa!.id);
    empresa!.abertaManual = nova;
    notifyListeners();
  }

  Future<void> verificarAssinatura() async {
    try {
      final r = await _db.rpc('minha_assinatura');
      assinatura = r == null ? null : Map<String, dynamic>.from(r as Map);
      if (!assinaturaLiberada) await silenciar();
      notifyListeners();
    } catch (_) {
      // sem internet: mantém o último estado
    }
  }

  /// Salva campos da loja (colunas do banco) e recarrega a empresa
  Future<void> atualizarEmpresa(Map<String, dynamic> dados) async {
    if (empresa == null) return;
    final j = await _db.from('empresas').update(dados).eq('id', empresa!.id).select(camposEmpresa).single();
    empresa = EmpresaLojista.fromJson(j);
    notifyListeners();
  }

  Future<void> encerrar() async {
    _intervalo?.cancel();
    if (_canal != null) await _db.removeChannel(_canal!);
    _canal = null;
    await silenciar();
    empresa = null;
    assinatura = null;
    pedidos = [];
    _conhecidos.clear();
    _jaImpressosAuto.clear();
    notifyListeners();
  }
}
