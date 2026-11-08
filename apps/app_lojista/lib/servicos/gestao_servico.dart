import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/gestao.dart';
import 'pedidos_servico.dart';

/// Cadastro da loja feito pelo app: cardápio, opções, bairros e horários.
/// Mesmo acesso que o antigo painel web: RLS garante que só mexe na própria loja.
class GestaoServico extends ChangeNotifier {
  GestaoServico._();
  static final instancia = GestaoServico._();

  SupabaseClient get _db => Supabase.instance.client;
  int get _idEmpresa => PedidosServico.instancia.empresa!.id;

  List<Categoria> categorias = [];
  List<Produto> produtos = [];
  List<GrupoOpcoes> grupos = [];
  List<Bairro> bairros = [];
  bool carregandoCardapio = false;
  bool cardapioCarregado = false;

  List<Produto> produtosDa(int idCategoria) =>
      produtos.where((p) => p.idCategoria == idCategoria).toList()..sort(compararOrdem);

  GrupoOpcoes? grupo(int id) => grupos.where((g) => g.id == id).firstOrNull;

  // ---------------- carga ----------------

  Future<void> carregarCardapio() async {
    // sem notificar aqui: pode ser chamado durante a montagem de uma tela
    carregandoCardapio = true;
    try {
      final r = await Future.wait([
        _db.from('categorias').select().eq('id_empresa', _idEmpresa).order('ordem_exibicao').order('id'),
        _db
            .from('produtos')
            .select('*, produtos_grupos_opcoes(id_grupo_opcao, ordem_exibicao)')
            .eq('id_empresa', _idEmpresa)
            .order('ordem_exibicao')
            .order('id'),
        _db.from('grupos_opcoes').select('*, opcoes(*)').eq('id_empresa', _idEmpresa).order('ordem_exibicao').order('id'),
      ]);
      categorias = (r[0] as List).map((j) => Categoria.fromJson(j)).toList();
      produtos = (r[1] as List).map((j) => Produto.fromJson(j)).toList();
      grupos = (r[2] as List).map((j) => GrupoOpcoes.fromJson(j)).toList();
      cardapioCarregado = true;
    } finally {
      carregandoCardapio = false;
      notifyListeners();
    }
  }

  void limpar() {
    categorias = [];
    produtos = [];
    grupos = [];
    bairros = [];
    cardapioCarregado = false;
  }

  /// Troca o item com o vizinho e grava só o ordem_exibicao que mudou
  Future<void> mover<T extends Ordenavel>(String tabela, List<T> lista, int indice, int direcao) async {
    final alvo = indice + direcao;
    if (alvo < 0 || alvo >= lista.length) return;
    final item = lista.removeAt(indice);
    lista.insert(alvo, item);
    final mudados = <T>[];
    for (var i = 0; i < lista.length; i++) {
      if (lista[i].ordemExibicao != i + 1) {
        lista[i].ordemExibicao = i + 1;
        mudados.add(lista[i]);
      }
    }
    notifyListeners();
    await Future.wait(
        mudados.map((m) => _db.from(tabela).update({'ordem_exibicao': m.ordemExibicao}).eq('id', m.id)));
  }

  // ---------------- categorias ----------------

  Future<void> criarCategoria(String nome) async {
    final j = await _db
        .from('categorias')
        .insert({'id_empresa': _idEmpresa, 'nome_categoria': nome, 'ordem_exibicao': categorias.length + 1})
        .select()
        .single();
    categorias.add(Categoria.fromJson(j));
    notifyListeners();
  }

  Future<void> renomearCategoria(Categoria c, String nome) async {
    await _db.from('categorias').update({'nome_categoria': nome}).eq('id', c.id);
    c.nomeCategoria = nome;
    notifyListeners();
  }

  Future<void> alternarCategoria(Categoria c) async {
    await _db.from('categorias').update({'ativo': !c.ativo}).eq('id', c.id);
    c.ativo = !c.ativo;
    notifyListeners();
  }

  /// Apaga a categoria e (pelo cascade do banco) os produtos dela
  Future<void> excluirCategoria(Categoria c) async {
    await _db.from('categorias').delete().eq('id', c.id);
    categorias.remove(c);
    produtos.removeWhere((p) => p.idCategoria == c.id);
    notifyListeners();
  }

  // ---------------- produtos ----------------

  /// Cria ou atualiza o produto e grava os grupos de opções. Retorna o id.
  Future<int> salvarProduto({
    Produto? existente,
    required int idCategoria,
    required String nome,
    String? descricao,
    required double preco,
    String? fotoUrl,
    required List<int> idsGrupos,
  }) async {
    final dados = {
      'nome_produto': nome,
      'descricao_produto': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
      'preco_produto': preco,
      'id_categoria': idCategoria,
      'foto_url': fotoUrl,
    };
    late int id;
    if (existente != null) {
      await _db.from('produtos').update(dados).eq('id', existente.id);
      id = existente.id;
    } else {
      final j = await _db
          .from('produtos')
          .insert({...dados, 'id_empresa': _idEmpresa, 'ordem_exibicao': produtosDa(idCategoria).length + 1})
          .select('id')
          .single();
      id = j['id'] as int;
    }
    await _db.rpc('salvar_grupos_do_produto', params: {'p_id_produto': id, 'p_ids_grupos': idsGrupos});
    await carregarCardapio();
    return id;
  }

  /// Disponível / esgotado
  Future<void> alternarProduto(Produto p) async {
    await _db.from('produtos').update({'ativo': !p.ativo}).eq('id', p.id);
    p.ativo = !p.ativo;
    notifyListeners();
  }

  Future<void> excluirProduto(Produto p) async {
    await _db.from('produtos').delete().eq('id', p.id);
    produtos.remove(p);
    notifyListeners();
  }

  // ---------------- grupos e opções ----------------

  Future<void> criarGrupo(String nome, {int minimo = 0, int maximo = 1}) async {
    final j = await _db
        .from('grupos_opcoes')
        .insert({
          'id_empresa': _idEmpresa,
          'nome_grupo': nome,
          'minimo_selecao': minimo,
          'maximo_selecao': maximo,
          'ordem_exibicao': grupos.length + 1,
        })
        .select('*, opcoes(*)')
        .single();
    grupos.add(GrupoOpcoes.fromJson(j));
    notifyListeners();
  }

  /// Atualiza nome e regra. O banco exige maximo >= minimo e maximo >= 1.
  Future<void> atualizarGrupo(GrupoOpcoes g, {String? nome, bool? obrigatorio, int? maximo}) async {
    final novoMax = (maximo ?? g.maximoSelecao).clamp(1, 50);
    final novoMin = (obrigatorio ?? g.obrigatorio) ? 1 : 0;
    final dados = {'nome_grupo': nome ?? g.nomeGrupo, 'minimo_selecao': novoMin, 'maximo_selecao': novoMax};
    await _db.from('grupos_opcoes').update(dados).eq('id', g.id);
    g
      ..nomeGrupo = dados['nome_grupo'] as String
      ..minimoSelecao = novoMin
      ..maximoSelecao = novoMax;
    notifyListeners();
  }

  Future<void> alternarGrupo(GrupoOpcoes g) async {
    await _db.from('grupos_opcoes').update({'ativo': !g.ativo}).eq('id', g.id);
    g.ativo = !g.ativo;
    notifyListeners();
  }

  Future<void> excluirGrupo(GrupoOpcoes g) async {
    await _db.from('grupos_opcoes').delete().eq('id', g.id);
    grupos.remove(g);
    for (final p in produtos) {
      p.idsGrupos.remove(g.id);
    }
    notifyListeners();
  }

  Future<void> criarOpcao(GrupoOpcoes g, String nome, double preco) async {
    final j = await _db
        .from('opcoes')
        .insert({
          'id_empresa': _idEmpresa,
          'id_grupo_opcao': g.id,
          'nome_opcao': nome,
          'preco_adicional': preco,
          'ordem_exibicao': g.opcoes.length + 1,
        })
        .select()
        .single();
    g.opcoes.add(Opcao.fromJson(j));
    notifyListeners();
  }

  Future<void> atualizarOpcao(Opcao o, {String? nome, double? preco}) async {
    final dados = {'nome_opcao': nome ?? o.nomeOpcao, 'preco_adicional': preco ?? o.precoAdicional};
    await _db.from('opcoes').update(dados).eq('id', o.id);
    o
      ..nomeOpcao = dados['nome_opcao'] as String
      ..precoAdicional = dados['preco_adicional'] as double;
    notifyListeners();
  }

  Future<void> alternarOpcao(Opcao o) async {
    await _db.from('opcoes').update({'ativo': !o.ativo}).eq('id', o.id);
    o.ativo = !o.ativo;
    notifyListeners();
  }

  Future<void> excluirOpcao(GrupoOpcoes g, Opcao o) async {
    await _db.from('opcoes').delete().eq('id', o.id);
    g.opcoes.remove(o);
    notifyListeners();
  }

  // ---------------- bairros ----------------

  Future<void> carregarBairros() async {
    final dados = await _db.from('bairros_entrega').select().eq('id_empresa', _idEmpresa).order('nome_bairro');
    bairros = (dados as List).map((j) => Bairro.fromJson(j)).toList();
    notifyListeners();
  }

  /// Aceita vários nomes separados por vírgula ou linha, todos com a mesma taxa
  Future<int> adicionarBairros(String nomes, double taxa) async {
    final lista = nomes.split(RegExp(r'[,\n]')).map((n) => n.trim()).where((n) => n.isNotEmpty).toSet().toList();
    if (lista.isEmpty) return 0;
    await _db.from('bairros_entrega').insert([
      for (final n in lista) {'id_empresa': _idEmpresa, 'nome_bairro': n, 'taxa_entrega': taxa},
    ]);
    await carregarBairros();
    return lista.length;
  }

  Future<void> atualizarBairro(Bairro b, {double? taxa, bool? ativo}) async {
    final dados = {'taxa_entrega': taxa ?? b.taxaEntrega, 'ativo': ativo ?? b.ativo};
    await _db.from('bairros_entrega').update(dados).eq('id', b.id);
    b
      ..taxaEntrega = dados['taxa_entrega'] as double
      ..ativo = dados['ativo'] as bool;
    notifyListeners();
  }

  Future<void> excluirBairro(Bairro b) async {
    await _db.from('bairros_entrega').delete().eq('id', b.id);
    bairros.remove(b);
    notifyListeners();
  }

  // ---------------- horários ----------------

  Future<List<Horario>> carregarHorarios() async {
    final dados = await _db
        .from('horarios_funcionamento')
        .select()
        .eq('id_empresa', _idEmpresa)
        .order('dia_semana')
        .order('hora_abertura');
    return (dados as List).map((j) => Horario.fromJson(j)).toList();
  }

  /// Substitui todos os horários (apaga e insere de novo)
  Future<void> salvarHorarios(List<Horario> horarios) async {
    final validos = horarios.where((h) => h.horaAbertura != h.horaFechamento).toList();
    await _db.from('horarios_funcionamento').delete().eq('id_empresa', _idEmpresa);
    if (validos.isNotEmpty) {
      await _db.from('horarios_funcionamento').insert([for (final h in validos) h.toJson(_idEmpresa)]);
    }
  }
}
