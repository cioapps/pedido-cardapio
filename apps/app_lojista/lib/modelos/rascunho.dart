double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

/// Opção escolhida dentro de um item (formato do criar_pedido)
class OpcaoRascunho {
  final int idOpcao;
  int quantidade;
  OpcaoRascunho(this.idOpcao, this.quantidade);

  Map<String, dynamic> toJson() => {'id_opcao': idOpcao, 'quantidade': quantidade};
}

class ItemRascunho {
  final int idProduto;
  int quantidade;
  String observacaoItem;
  final List<OpcaoRascunho> opcoes;

  ItemRascunho({required this.idProduto, required this.quantidade, this.observacaoItem = '', required this.opcoes});

  factory ItemRascunho.fromJson(Map<String, dynamic> j) => ItemRascunho(
        idProduto: j['id_produto'] as int,
        quantidade: (j['quantidade'] as num?)?.toInt() ?? 1,
        observacaoItem: j['observacao_item'] as String? ?? '',
        opcoes: ((j['opcoes'] as List?) ?? [])
            .map((o) => OpcaoRascunho(o['id_opcao'] as int, (o['quantidade'] as num?)?.toInt() ?? 1))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id_produto': idProduto,
        'quantidade': quantidade,
        'observacao_item': observacaoItem,
        'opcoes': opcoes.map((o) => o.toJson()).toList(),
      };
}

/// Dados do pedido que a IA montou (o lojista pode editar antes de confirmar)
class DadosRascunho {
  String nomeCliente;
  String telefoneCliente;
  String logradouro;
  String numeroEndereco;
  String complemento;
  String pontoReferencia;
  int? idBairroEntrega;
  String? formaPagamento;
  double? trocoPara;
  String observacaoPedido;
  final List<ItemRascunho> itens;

  DadosRascunho.fromJson(Map<String, dynamic> j)
      : nomeCliente = j['nome_cliente'] as String? ?? '',
        telefoneCliente = j['telefone_cliente'] as String? ?? '',
        logradouro = j['logradouro'] as String? ?? '',
        numeroEndereco = j['numero_endereco'] as String? ?? '',
        complemento = j['complemento'] as String? ?? '',
        pontoReferencia = j['ponto_referencia'] as String? ?? '',
        idBairroEntrega = j['id_bairro_entrega'] as int?,
        formaPagamento = j['forma_pagamento'] as String?,
        trocoPara = j['troco_para'] == null ? null : _num(j['troco_para']),
        observacaoPedido = j['observacao_pedido'] as String? ?? '',
        itens = ((j['itens'] as List?) ?? []).map((i) => ItemRascunho.fromJson(i as Map<String, dynamic>)).toList();

  Map<String, dynamic> toJson() => {
        'nome_cliente': nomeCliente.trim(),
        'telefone_cliente': telefoneCliente,
        'logradouro': logradouro.trim(),
        'numero_endereco': numeroEndereco.trim(),
        'complemento': complemento.trim(),
        'ponto_referencia': pontoReferencia.trim(),
        'id_bairro_entrega': idBairroEntrega,
        'forma_pagamento': formaPagamento,
        'troco_para': formaPagamento == 'dinheiro' ? trocoPara : null,
        'observacao_pedido': observacaoPedido.trim(),
        'itens': itens.map((i) => i.toJson()).toList(),
      };
}

class Rascunho {
  final int id;
  final int idConversa;
  final String statusRascunho; // montando | pronto
  final DadosRascunho dados;
  final List<String> pendencias;
  final String? resumoIa;
  final double valorEstimado;
  final DateTime atualizadoEm;
  final String? nomeContato;
  final String? telefoneContato;

  Rascunho.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        idConversa = j['id_conversa'] as int,
        statusRascunho = j['status_rascunho'] as String,
        dados = DadosRascunho.fromJson((j['dados_pedido'] as Map?)?.cast<String, dynamic>() ?? {}),
        pendencias = ((j['pendencias'] as List?) ?? []).map((p) => '$p').toList(),
        resumoIa = j['resumo_ia'] as String?,
        valorEstimado = _num(j['valor_estimado']),
        atualizadoEm = DateTime.parse(j['atualizado_em'] as String),
        nomeContato = (j['conversas_whatsapp'] as Map?)?['nome_contato'] as String?,
        telefoneContato = (j['conversas_whatsapp'] as Map?)?['telefone_contato'] as String?;

  bool get pronto => statusRascunho == 'pronto';
  String get titulo => (dados.nomeCliente.isNotEmpty ? dados.nomeCliente : nomeContato) ?? telefoneContato ?? 'Cliente';
}

class MensagemWhatsapp {
  final bool enviadaPelaLoja;
  final String tipo;
  final String texto;
  final DateTime enviadaEm;

  MensagemWhatsapp.fromJson(Map<String, dynamic> j)
      : enviadaPelaLoja = j['enviada_pela_loja'] as bool,
        tipo = j['tipo_mensagem'] as String,
        texto = (j['tipo_mensagem'] == 'audio'
                ? '🎤 ${j['transcricao_audio'] ?? '(áudio)'}'
                : (j['texto_mensagem'] as String?)) ??
            '(${j['tipo_mensagem']})',
        enviadaEm = DateTime.parse(j['enviada_em'] as String);
}

// ---------- Cardápio (para mostrar nomes e preços dos IDs) ----------
class OpcaoCardapio {
  final int id;
  final String nome;
  final String nomeGrupo;
  final double preco;
  OpcaoCardapio(this.id, this.nome, this.nomeGrupo, this.preco);
}

class GrupoCardapio {
  final int id;
  final String nome;
  final int minimo;
  final int maximo;
  final List<OpcaoCardapio> opcoes;
  GrupoCardapio(this.id, this.nome, this.minimo, this.maximo, this.opcoes);
}

class ProdutoCardapio {
  final int id;
  final String nome;
  final double preco;
  final List<GrupoCardapio> grupos;
  ProdutoCardapio(this.id, this.nome, this.preco, this.grupos);
}

class BairroCardapio {
  final int id;
  final String nome;
  final double taxa;
  BairroCardapio(this.id, this.nome, this.taxa);
}

class CardapioResumo {
  final Map<int, ProdutoCardapio> produtos = {};
  final Map<int, OpcaoCardapio> opcoes = {};
  final List<BairroCardapio> bairros = [];

  CardapioResumo.fromJson(Map<String, dynamic> j) {
    for (final c in (j['categorias'] as List? ?? [])) {
      for (final p in (c['produtos'] as List? ?? [])) {
        final grupos = <GrupoCardapio>[];
        for (final g in (p['grupos'] as List? ?? [])) {
          final opcoes = <OpcaoCardapio>[];
          for (final o in (g['opcoes'] as List? ?? [])) {
            final opcao = OpcaoCardapio(o['id'] as int, o['nome_opcao'] as String, g['nome_grupo'] as String, _num(o['preco_adicional']));
            opcoes.add(opcao);
            this.opcoes[opcao.id] = opcao;
          }
          grupos.add(GrupoCardapio(g['id'] as int, g['nome_grupo'] as String, g['minimo_selecao'] as int, g['maximo_selecao'] as int, opcoes));
        }
        produtos[p['id'] as int] = ProdutoCardapio(p['id'] as int, p['nome_produto'] as String, _num(p['preco_produto']), grupos);
      }
    }
    for (final b in (j['bairros'] as List? ?? [])) {
      bairros.add(BairroCardapio(b['id'] as int, b['nome_bairro'] as String, _num(b['taxa_entrega'])));
    }
  }

  double precoItem(ItemRascunho item) {
    final p = produtos[item.idProduto];
    if (p == null) return 0;
    var unit = p.preco;
    for (final o in item.opcoes) {
      unit += (opcoes[o.idOpcao]?.preco ?? 0) * o.quantidade;
    }
    return unit * item.quantidade;
  }

  double total(DadosRascunho d) {
    final itens = d.itens.fold<double>(0, (s, i) => s + precoItem(i));
    final taxa = bairros.where((b) => b.id == d.idBairroEntrega).firstOrNull?.taxa ?? 0;
    return itens + taxa;
  }
}
