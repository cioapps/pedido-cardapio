import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/rascunho.dart';
import 'impressora_servico.dart';
import 'pedidos_servico.dart';

/// Rascunhos de pedido montados pela IA a partir das conversas do WhatsApp
class WhatsappServico extends ChangeNotifier {
  WhatsappServico._();
  static final instancia = WhatsappServico._();

  SupabaseClient get _db => Supabase.instance.client;

  List<Rascunho> rascunhos = [];
  CardapioResumo? cardapio;
  String? erro;
  int? _idEmpresa;

  RealtimeChannel? _canal;
  final _player = AudioPlayer();
  final Set<int> _prontosAvisados = {};
  bool _primeiraCarga = true;

  int get quantidadeProntos => rascunhos.where((r) => r.pronto).length;

  Future<void> iniciar(int idEmpresa, String slugEmpresa) async {
    _idEmpresa = idEmpresa;
    _primeiraCarga = true;
    await _player.setReleaseMode(ReleaseMode.release);
    await carregarCardapio(slugEmpresa);
    await recarregar();
    if (_canal != null) await _db.removeChannel(_canal!);
    _canal = _db
        .channel('rascunhos-app-$idEmpresa')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rascunhos_pedido',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id_empresa', value: idEmpresa),
          callback: (_) => recarregar(),
        )
        .subscribe();
  }

  Future<void> carregarCardapio(String slugEmpresa) async {
    final dados = await _db.rpc('obter_cardapio', params: {'p_slug': slugEmpresa});
    if (dados != null) cardapio = CardapioResumo.fromJson((dados as Map).cast<String, dynamic>());
  }

  Future<void> recarregar() async {
    if (_idEmpresa == null) return;
    try {
      final dados = await _db
          .from('rascunhos_pedido')
          .select('*, conversas_whatsapp(nome_contato, telefone_contato)')
          .eq('id_empresa', _idEmpresa!)
          .inFilter('status_rascunho', ['montando', 'pronto'])
          .order('atualizado_em', ascending: false);
      rascunhos = (dados as List).map((j) => Rascunho.fromJson(j as Map<String, dynamic>)).toList();
      erro = null;

      // avisa (uma vez) quando um rascunho fica pronto para confirmar
      final novosProntos = rascunhos.where((r) => r.pronto && !_prontosAvisados.contains(r.id)).toList();
      _prontosAvisados.addAll(novosProntos.map((r) => r.id));
      if (!_primeiraCarga && novosProntos.isNotEmpty) {
        await _player.play(AssetSource('sons/alerta.wav'), volume: 1);
      }
      _primeiraCarga = false;
    } catch (e) {
      erro = 'Não foi possível carregar os pedidos do WhatsApp.';
    }
    notifyListeners();
  }

  Future<List<MensagemWhatsapp>> mensagens(int idConversa) async {
    final dados = await _db
        .from('mensagens_whatsapp')
        .select('enviada_pela_loja, tipo_mensagem, texto_mensagem, transcricao_audio, enviada_em')
        .eq('id_conversa', idConversa)
        .order('enviada_em', ascending: false)
        .limit(40);
    return (dados as List).map((j) => MensagemWhatsapp.fromJson(j as Map<String, dynamic>)).toList().reversed.toList();
  }

  /// Cria o pedido (já aceito) e imprime conforme a configuração da impressora
  Future<int> confirmar(Rascunho r, DadosRascunho dados) async {
    final resultado = await _db.rpc('confirmar_rascunho', params: {
      'p_id_rascunho': r.id,
      'p_dados': dados.toJson(),
    }) as Map;
    final idPedido = resultado['id_pedido'] as int;

    final pedidos = PedidosServico.instancia;
    await pedidos.recarregar();
    final imp = ImpressoraServico.instancia;
    if (imp.configurada && imp.config.automatica != ImpressaoAutomatica.desligada) {
      final pedido = pedidos.pedidos.where((p) => p.id == idPedido).firstOrNull;
      if (pedido != null) {
        try {
          await pedidos.imprimir(pedido);
        } catch (e) {
          erro = 'Pedido confirmado, mas a impressão falhou: $e';
        }
      }
    }
    await recarregar();
    return resultado['numero_pedido'] as int;
  }

  Future<void> descartar(Rascunho r, {bool ignorarContato = false}) async {
    await _db.from('rascunhos_pedido').update({'status_rascunho': 'descartado'}).eq('id', r.id);
    if (ignorarContato) {
      await _db.from('conversas_whatsapp').update({'ignorar_conversa': true}).eq('id', r.idConversa);
    }
    await recarregar();
  }

  // ---------- Conexão (Edge Function whatsapp-conexao) ----------
  Future<Map<String, dynamic>> conexao(String acao, {String? telefone}) async {
    final resposta = await _db.functions.invoke('whatsapp-conexao', body: {
      'acao': acao,
      'telefone': ?telefone,
    });
    return (resposta.data as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> preferencias() async {
    if (_idEmpresa == null) return null;
    return await _db
        .from('conexoes_whatsapp')
        .select('ia_ativa, transcrever_audio')
        .eq('id_empresa', _idEmpresa!)
        .maybeSingle();
  }

  Future<void> salvarPreferencia(String campo, bool valor) async {
    if (_idEmpresa == null) return;
    await _db.from('conexoes_whatsapp').update({campo: valor}).eq('id_empresa', _idEmpresa!);
  }

  Future<void> encerrar() async {
    if (_canal != null) await _db.removeChannel(_canal!);
    _canal = null;
    _idEmpresa = null;
    rascunhos = [];
    _prontosAvisados.clear();
    notifyListeners();
  }
}
