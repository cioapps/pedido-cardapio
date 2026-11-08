double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

class OpcaoItemPedido {
  final String nomeGrupo;
  final String nomeOpcao;
  final int quantidade;
  final double precoAdicional;

  OpcaoItemPedido.fromJson(Map<String, dynamic> j)
      : nomeGrupo = j['nome_grupo'] as String,
        nomeOpcao = j['nome_opcao'] as String,
        quantidade = j['quantidade'] as int,
        precoAdicional = _num(j['preco_adicional']);

  String get descricao => quantidade > 1 ? '${quantidade}x $nomeOpcao' : nomeOpcao;
}

class ItemPedido {
  final int id;
  final String nomeProduto;
  final int quantidade;
  final double precoUnitario;
  final double valorTotalItem;
  final String? observacaoItem;
  final List<OpcaoItemPedido> opcoes;

  ItemPedido.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nomeProduto = j['nome_produto'] as String,
        quantidade = j['quantidade'] as int,
        precoUnitario = _num(j['preco_unitario']),
        valorTotalItem = _num(j['valor_total_item']),
        observacaoItem = j['observacao_item'] as String?,
        opcoes = ((j['itens_pedido_opcoes'] as List?) ?? [])
            .map((o) => OpcaoItemPedido.fromJson(o as Map<String, dynamic>))
            .toList();
}

class Pedido {
  final int id;
  final int numeroPedido;
  final String nomeCliente;
  final String telefoneCliente;
  final String logradouro;
  final String numeroEndereco;
  final String? complemento;
  final String? pontoReferencia;
  final String nomeBairro;
  final String formaPagamento;
  final double? trocoPara;
  final double subtotal;
  final double taxaEntrega;
  final double valorTotal;
  final String? observacaoPedido;
  final String statusPedido;
  final bool impresso;
  final DateTime criadoEm;
  final String origemPedido;
  final List<ItemPedido> itens;

  Pedido.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        numeroPedido = j['numero_pedido'] as int,
        nomeCliente = j['nome_cliente'] as String,
        telefoneCliente = j['telefone_cliente'] as String,
        logradouro = j['logradouro'] as String,
        numeroEndereco = j['numero_endereco'] as String,
        complemento = j['complemento'] as String?,
        pontoReferencia = j['ponto_referencia'] as String?,
        nomeBairro = j['nome_bairro'] as String,
        formaPagamento = j['forma_pagamento'] as String,
        trocoPara = j['troco_para'] == null ? null : _num(j['troco_para']),
        subtotal = _num(j['subtotal']),
        taxaEntrega = _num(j['taxa_entrega']),
        valorTotal = _num(j['valor_total']),
        observacaoPedido = j['observacao_pedido'] as String?,
        statusPedido = j['status_pedido'] as String,
        impresso = j['impresso'] as bool? ?? false,
        criadoEm = DateTime.parse(j['criado_em'] as String),
        origemPedido = j['origem_pedido'] as String? ?? 'cardapio',
        itens = (((j['itens_pedido'] as List?) ?? [])
                .map((i) => ItemPedido.fromJson(i as Map<String, dynamic>))
                .toList())
          ..sort((a, b) => a.id.compareTo(b.id));

  String get enderecoCompleto =>
      '$logradouro, $numeroEndereco${complemento != null && complemento!.isNotEmpty ? ' - $complemento' : ''}';

  bool get finalizado => statusPedido == 'entregue' || statusPedido == 'cancelado';

  /// Próximo status e o texto do botão
  (String, String)? get proximaEtapa => switch (statusPedido) {
        'novo' => ('aceito', 'Aceitar pedido'),
        'aceito' => ('em_preparo', 'Iniciar preparo'),
        'em_preparo' => ('saiu_entrega', 'Saiu para entrega'),
        'saiu_entrega' => ('entregue', 'Marcar como entregue'),
        _ => null,
      };
}

/// Colunas de empresas que o app carrega (mesmas do antigo painel web)
const camposEmpresa = 'id, nome_empresa, slug_empresa, telefone_whatsapp, logo_url, cor_principal, endereco_empresa, '
    'pedido_minimo, tempo_entrega_minutos, aberta_manual, usar_horarios, modulo_cardapio_ativo, modulo_whatsapp_ativo';

class EmpresaLojista {
  final int id;
  String nomeEmpresa;
  final String slugEmpresa;
  String? telefoneWhatsapp;
  String? logoUrl;
  String corPrincipal;
  String? enderecoEmpresa;
  double pedidoMinimo;
  int tempoEntregaMinutos;
  bool usarHorarios;
  final bool moduloCardapio;
  final bool moduloWhatsapp;
  bool abertaManual;

  EmpresaLojista.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nomeEmpresa = j['nome_empresa'] as String,
        slugEmpresa = j['slug_empresa'] as String,
        telefoneWhatsapp = j['telefone_whatsapp'] as String?,
        logoUrl = j['logo_url'] as String?,
        corPrincipal = j['cor_principal'] as String? ?? '#E63946',
        enderecoEmpresa = j['endereco_empresa'] as String?,
        pedidoMinimo = _num(j['pedido_minimo']),
        tempoEntregaMinutos = j['tempo_entrega_minutos'] as int? ?? 45,
        usarHorarios = j['usar_horarios'] as bool? ?? false,
        moduloCardapio = j['modulo_cardapio_ativo'] as bool? ?? true,
        moduloWhatsapp = j['modulo_whatsapp_ativo'] as bool? ?? false,
        abertaManual = j['aberta_manual'] as bool;
}
