/**
 * Dados do cliente guardados SÓ neste aparelho (localStorage).
 *
 * Por que não buscar no servidor pelo telefone: qualquer pessoa poderia digitar o número
 * de outra e ver nome e endereço dela. Aqui o cadastro é do próprio cliente e vale para
 * todas as lojas que ele abrir neste aparelho; o bairro é casado pelo nome com os bairros
 * que cada loja atende.
 */
import type { BairroCardapio } from '../lib/tipos'

export interface EnderecoSalvo {
  id: string
  logradouro: string
  numero_endereco: string
  complemento: string
  ponto_referencia: string
  nome_bairro: string
}

export interface PerfilCliente {
  telefone: string
  nome_cliente: string
  enderecos: EnderecoSalvo[]
  /** id do endereço padrão (o primeiro cadastrado, até o cliente trocar) */
  id_endereco_padrao: string | null
  ultimo_pagamento?: FormaPagamento
  atualizado_em: string
}

export type FormaPagamento = 'dinheiro' | 'cartao' | 'pix'

export interface PedidoSalvo {
  codigo: string
  slug: string
  nome_empresa: string
  cor_principal: string
  numero_pedido: number
  valor_total: number
  criado_em: string
}

const CHAVE_PERFIS = 'cardapio:perfis'
const CHAVE_ULTIMO_TELEFONE = 'cardapio:ultimo_telefone'
const CHAVE_PEDIDOS = 'cardapio:pedidos'
const CHAVE_ANTIGA = 'cardapio:cliente'
const MAXIMO_PEDIDOS = 30
const MAXIMO_ENDERECOS = 5

function ler<T>(chave: string, padrao: T): T {
  try {
    const bruto = localStorage.getItem(chave)
    return bruto ? (JSON.parse(bruto) as T) : padrao
  } catch {
    return padrao
  }
}

function gravar(chave: string, valor: unknown) {
  try {
    localStorage.setItem(chave, JSON.stringify(valor))
  } catch {
    /* modo anônimo ou armazenamento cheio: segue sem lembrar */
  }
}

function remover(chave: string) {
  try {
    localStorage.removeItem(chave)
  } catch {
    /* sem armazenamento */
  }
}

export const soDigitos = (tel: string) => tel.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
export const telefoneCompleto = (tel: string) => /^\d{10,11}$/.test(soDigitos(tel))

const novoId = () => Math.random().toString(36).slice(2, 10)

const normalizar = (texto: string) =>
  texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()

const mesmoEndereco = (a: Omit<EnderecoSalvo, 'id'>, b: Omit<EnderecoSalvo, 'id'>) =>
  normalizar(a.logradouro) === normalizar(b.logradouro) &&
  normalizar(a.numero_endereco) === normalizar(b.numero_endereco) &&
  normalizar(a.complemento) === normalizar(b.complemento) &&
  normalizar(a.nome_bairro) === normalizar(b.nome_bairro)

type Perfis = Record<string, PerfilCliente>

/** Converte o formato antigo (um cliente só) para o novo, uma única vez */
function lerPerfis(): Perfis {
  const perfis = ler<Perfis>(CHAVE_PERFIS, {})
  const antigo = ler<{
    nome_cliente?: string
    telefone_cliente?: string
    logradouro?: string
    numero_endereco?: string
    complemento?: string
    ponto_referencia?: string
  } | null>(CHAVE_ANTIGA, null)
  if (antigo?.telefone_cliente && telefoneCompleto(antigo.telefone_cliente)) {
    const tel = soDigitos(antigo.telefone_cliente)
    if (!perfis[tel] && antigo.nome_cliente) {
      const endereco: EnderecoSalvo | null = antigo.logradouro
        ? {
            id: novoId(),
            logradouro: antigo.logradouro,
            numero_endereco: antigo.numero_endereco ?? '',
            complemento: antigo.complemento ?? '',
            ponto_referencia: antigo.ponto_referencia ?? '',
            nome_bairro: '',
          }
        : null
      perfis[tel] = {
        telefone: tel,
        nome_cliente: antigo.nome_cliente,
        enderecos: endereco ? [endereco] : [],
        id_endereco_padrao: endereco?.id ?? null,
        atualizado_em: new Date().toISOString(),
      }
      gravar(CHAVE_PERFIS, perfis)
      gravar(CHAVE_ULTIMO_TELEFONE, tel)
    }
    remover(CHAVE_ANTIGA)
  }
  return perfis
}

export const buscarPerfil = (telefone: string): PerfilCliente | null =>
  telefoneCompleto(telefone) ? (lerPerfis()[soDigitos(telefone)] ?? null) : null

export const ultimoTelefone = (): string => {
  lerPerfis() // garante a conversão do formato antigo
  return ler<string>(CHAVE_ULTIMO_TELEFONE, '')
}

/** Salva o cliente depois de um pedido feito. Endereço repetido não duplica. */
export function salvarPerfil(
  telefone: string,
  nome: string,
  endereco: Omit<EnderecoSalvo, 'id'>,
  tornarPadrao: boolean,
  pagamento: FormaPagamento,
  idSubstituido?: string | null,
): void {
  const tel = soDigitos(telefone)
  const perfis = lerPerfis()
  const atual = perfis[tel]
  // endereço editado: sai o antigo, entra o novo no mesmo lugar de padrão
  const enderecos = (atual?.enderecos ?? []).filter((e) => e.id !== idSubstituido)
  const eraPadrao = !!idSubstituido && atual?.id_endereco_padrao === idSubstituido
  const existente = enderecos.find((e) => mesmoEndereco(e, endereco))
  const id = existente?.id ?? novoId()
  const atualizado: EnderecoSalvo = { ...endereco, id }
  const lista = existente
    ? enderecos.map((e) => (e.id === id ? atualizado : e))
    : [atualizado, ...enderecos].slice(0, MAXIMO_ENDERECOS)
  const padraoAtual = atual?.id_endereco_padrao
  const padraoValido = padraoAtual && lista.some((e) => e.id === padraoAtual)

  perfis[tel] = {
    telefone: tel,
    nome_cliente: nome.trim(),
    enderecos: lista,
    id_endereco_padrao: tornarPadrao || eraPadrao || !padraoValido ? id : padraoAtual,
    ultimo_pagamento: pagamento,
    atualizado_em: new Date().toISOString(),
  }
  gravar(CHAVE_PERFIS, perfis)
  gravar(CHAVE_ULTIMO_TELEFONE, tel)
}

export function removerEndereco(telefone: string, idEndereco: string): PerfilCliente | null {
  const tel = soDigitos(telefone)
  const perfis = lerPerfis()
  const perfil = perfis[tel]
  if (!perfil) return null
  const enderecos = perfil.enderecos.filter((e) => e.id !== idEndereco)
  perfis[tel] = {
    ...perfil,
    enderecos,
    id_endereco_padrao:
      perfil.id_endereco_padrao === idEndereco ? (enderecos[0]?.id ?? null) : perfil.id_endereco_padrao,
  }
  gravar(CHAVE_PERFIS, perfis)
  return perfis[tel]
}

/** "Não sou eu": apaga o cadastro deste telefone neste aparelho */
export function esquecerPerfil(telefone: string): void {
  const tel = soDigitos(telefone)
  const perfis = lerPerfis()
  delete perfis[tel]
  gravar(CHAVE_PERFIS, perfis)
  if (ler<string>(CHAVE_ULTIMO_TELEFONE, '') === tel) remover(CHAVE_ULTIMO_TELEFONE)
}

/** Bairro da loja com o mesmo nome do bairro salvo (cada loja tem sua lista) */
export const bairroDaLoja = (nomeBairro: string, bairros: BairroCardapio[]) => {
  const alvo = normalizar(nomeBairro)
  return alvo ? (bairros.find((b) => normalizar(b.nome_bairro) === alvo) ?? null) : null
}

export const resumoEndereco = (e: Pick<EnderecoSalvo, 'logradouro' | 'numero_endereco' | 'complemento'>) =>
  [`${e.logradouro}, ${e.numero_endereco}`, e.complemento].filter(Boolean).join(' · ')

// ---------- Pedidos feitos neste aparelho ----------
export const listarPedidos = (): PedidoSalvo[] => ler<PedidoSalvo[]>(CHAVE_PEDIDOS, [])

export function registrarPedido(pedido: PedidoSalvo): void {
  const lista = [pedido, ...listarPedidos().filter((p) => p.codigo !== pedido.codigo)]
  gravar(CHAVE_PEDIDOS, lista.slice(0, MAXIMO_PEDIDOS))
}
