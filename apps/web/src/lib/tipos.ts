// ---------- Cardápio público (retorno de obter_cardapio) ----------
export interface OpcaoCardapio {
  id: number
  nome_opcao: string
  preco_adicional: number
}

export interface GrupoCardapio {
  id: number
  nome_grupo: string
  minimo_selecao: number
  maximo_selecao: number
  opcoes: OpcaoCardapio[]
}

export interface ProdutoCardapio {
  id: number
  nome_produto: string
  descricao_produto: string | null
  preco_produto: number
  foto_url: string | null
  grupos: GrupoCardapio[]
}

export interface CategoriaCardapio {
  id: number
  nome_categoria: string
  produtos: ProdutoCardapio[]
}

export interface BairroCardapio {
  id: number
  nome_bairro: string
  taxa_entrega: number
}

export interface EmpresaCardapio {
  id: number
  nome_empresa: string
  slug_empresa: string
  telefone_whatsapp: string | null
  logo_url: string | null
  cor_principal: string
  endereco_empresa: string | null
  pedido_minimo: number
  tempo_entrega_minutos: number
  loja_aberta: boolean
  cardapio_ativo: boolean
  /** false quando a assinatura da loja está vencida ou bloqueada */
  loja_disponivel?: boolean
}

export interface Cardapio {
  empresa: EmpresaCardapio
  horarios: { dia_semana: number; hora_abertura: string; hora_fechamento: string }[]
  bairros: BairroCardapio[]
  categorias: CategoriaCardapio[]
}

// ---------- Carrinho ----------
export interface OpcaoEscolhida {
  id_opcao: number
  nome_opcao: string
  nome_grupo: string
  preco_adicional: number
  quantidade: number
}

export interface ItemCarrinho {
  chave: string
  id_produto: number
  nome_produto: string
  preco_unitario: number // produto + opções
  quantidade: number
  observacao_item: string
  opcoes: OpcaoEscolhida[]
}

// ---------- Tabelas (painel) ----------
export interface Empresa {
  id: number
  nome_empresa: string
  slug_empresa: string
  telefone_whatsapp: string | null
  logo_url: string | null
  cor_principal: string
  endereco_empresa: string | null
  pedido_minimo: number
  tempo_entrega_minutos: number
  aberta_manual: boolean
  usar_horarios: boolean
  modulo_cardapio_ativo: boolean
  modulo_whatsapp_ativo: boolean
}

export interface Categoria {
  id: number
  id_empresa: number
  nome_categoria: string
  ordem_exibicao: number
  ativo: boolean
}

export interface Produto {
  id: number
  id_empresa: number
  id_categoria: number
  nome_produto: string
  descricao_produto: string | null
  preco_produto: number
  foto_url: string | null
  ordem_exibicao: number
  ativo: boolean
  produtos_grupos_opcoes?: { id_grupo_opcao: number; ordem_exibicao: number }[]
}

export interface Opcao {
  id: number
  id_empresa: number
  id_grupo_opcao: number
  nome_opcao: string
  preco_adicional: number
  ordem_exibicao: number
  ativo: boolean
}

export interface GrupoOpcao {
  id: number
  id_empresa: number
  nome_grupo: string
  minimo_selecao: number
  maximo_selecao: number
  ordem_exibicao: number
  ativo: boolean
  opcoes?: Opcao[]
}

export interface BairroEntrega {
  id: number
  id_empresa: number
  nome_bairro: string
  taxa_entrega: number
  ativo: boolean
}

export interface HorarioFuncionamento {
  id: number
  id_empresa: number
  dia_semana: number
  hora_abertura: string
  hora_fechamento: string
}

export type StatusPedido =
  | 'novo'
  | 'aceito'
  | 'em_preparo'
  | 'saiu_entrega'
  | 'entregue'
  | 'cancelado'

export interface ItemPedido {
  id: number
  nome_produto: string
  quantidade: number
  preco_unitario: number
  valor_total_item: number
  observacao_item: string | null
  itens_pedido_opcoes: {
    id: number
    nome_grupo: string
    nome_opcao: string
    quantidade: number
    preco_adicional: number
  }[]
}

export interface Pedido {
  id: number
  numero_pedido: number
  nome_cliente: string
  telefone_cliente: string
  logradouro: string
  numero_endereco: string
  complemento: string | null
  ponto_referencia: string | null
  nome_bairro: string
  forma_pagamento: 'dinheiro' | 'cartao' | 'pix'
  troco_para: number | null
  subtotal: number
  taxa_entrega: number
  valor_total: number
  observacao_pedido: string | null
  status_pedido: StatusPedido
  impresso: boolean
  criado_em: string
  origem_pedido: 'cardapio' | 'whatsapp'
  itens_pedido?: ItemPedido[]
}
