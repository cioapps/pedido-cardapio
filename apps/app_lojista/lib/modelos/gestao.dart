// Modelos do cadastro da loja (cardápio, opções, entrega e horários).
// Os nomes das colunas seguem o banco: ver supabase/migrations/0001_estrutura.sql

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

/// Item que pode ser reordenado com as setas (grava ordem_exibicao)
abstract class Ordenavel {
  int get id;
  int get ordemExibicao;
  set ordemExibicao(int valor);
}

class Categoria implements Ordenavel {
  @override
  final int id;
  String nomeCategoria;
  @override
  int ordemExibicao;
  bool ativo;

  Categoria.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nomeCategoria = j['nome_categoria'] as String,
        ordemExibicao = j['ordem_exibicao'] as int? ?? 0,
        ativo = j['ativo'] as bool? ?? true;
}

class Produto implements Ordenavel {
  @override
  final int id;
  int idCategoria;
  String nomeProduto;
  String? descricaoProduto;
  double precoProduto;
  String? fotoUrl;
  @override
  int ordemExibicao;
  bool ativo;

  /// Grupos de opções vinculados, na ordem de exibição
  List<int> idsGrupos;

  Produto.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        idCategoria = j['id_categoria'] as int,
        nomeProduto = j['nome_produto'] as String,
        descricaoProduto = j['descricao_produto'] as String?,
        precoProduto = _num(j['preco_produto']),
        fotoUrl = j['foto_url'] as String?,
        ordemExibicao = j['ordem_exibicao'] as int? ?? 0,
        ativo = j['ativo'] as bool? ?? true,
        idsGrupos = (((j['produtos_grupos_opcoes'] as List?) ?? []).cast<Map<String, dynamic>>().toList()
              ..sort((a, b) => (a['ordem_exibicao'] as int? ?? 0).compareTo(b['ordem_exibicao'] as int? ?? 0)))
            .map((g) => g['id_grupo_opcao'] as int)
            .toList();
}

class Opcao implements Ordenavel {
  @override
  final int id;
  final int idGrupoOpcao;
  String nomeOpcao;
  double precoAdicional;
  @override
  int ordemExibicao;
  bool ativo;

  Opcao.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        idGrupoOpcao = j['id_grupo_opcao'] as int,
        nomeOpcao = j['nome_opcao'] as String,
        precoAdicional = _num(j['preco_adicional']),
        ordemExibicao = j['ordem_exibicao'] as int? ?? 0,
        ativo = j['ativo'] as bool? ?? true;
}

class GrupoOpcoes implements Ordenavel {
  @override
  final int id;
  String nomeGrupo;
  int minimoSelecao;
  int maximoSelecao;
  @override
  int ordemExibicao;
  bool ativo;
  List<Opcao> opcoes;

  GrupoOpcoes.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nomeGrupo = j['nome_grupo'] as String,
        minimoSelecao = j['minimo_selecao'] as int? ?? 0,
        maximoSelecao = j['maximo_selecao'] as int? ?? 1,
        ordemExibicao = j['ordem_exibicao'] as int? ?? 0,
        ativo = j['ativo'] as bool? ?? true,
        opcoes = (((j['opcoes'] as List?) ?? []).map((o) => Opcao.fromJson(o as Map<String, dynamic>)).toList())
          ..sort(compararOrdem);

  bool get obrigatorio => minimoSelecao > 0;

  /// "Obrigatório · escolha 1" / "Opcional · até 10"
  String get regra => obrigatorio
      ? (maximoSelecao == 1 ? 'Obrigatório · escolha 1' : 'Obrigatório · até $maximoSelecao')
      : (maximoSelecao == 1 ? 'Opcional · até 1' : 'Opcional · até $maximoSelecao');
}

class Bairro {
  final int id;
  String nomeBairro;
  double taxaEntrega;
  bool ativo;

  Bairro.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nomeBairro = j['nome_bairro'] as String,
        taxaEntrega = _num(j['taxa_entrega']),
        ativo = j['ativo'] as bool? ?? true;
}

/// Faixa de horário de um dia (0 = domingo). Horas em "HH:MM".
class Horario {
  int diaSemana;
  String horaAbertura;
  String horaFechamento;

  Horario(this.diaSemana, this.horaAbertura, this.horaFechamento);

  Horario.fromJson(Map<String, dynamic> j)
      : diaSemana = j['dia_semana'] as int,
        horaAbertura = (j['hora_abertura'] as String).substring(0, 5),
        horaFechamento = (j['hora_fechamento'] as String).substring(0, 5);

  Map<String, dynamic> toJson(int idEmpresa) => {
        'id_empresa': idEmpresa,
        'dia_semana': diaSemana,
        'hora_abertura': horaAbertura,
        'hora_fechamento': horaFechamento,
      };
}

const diasSemana = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

int compararOrdem(Ordenavel a, Ordenavel b) {
  final c = a.ordemExibicao.compareTo(b.ordemExibicao);
  return c != 0 ? c : a.id.compareTo(b.id);
}
