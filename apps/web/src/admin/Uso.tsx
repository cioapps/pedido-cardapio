import { useCallback, useEffect, useState } from 'react'
import { formatarDataHora, formatarMoeda, NOMES_PAGAMENTO, NOMES_STATUS } from '../lib/formatar'
import { mensagemErro, supabase } from '../lib/supabase'
import { tempoRelativo } from './tempo'

export interface UsoLoja {
  id_empresa: number
  pedidos_hoje: number
  pedidos_7d: number
  pedidos_30d: number
  faturamento_30d: number
  pedidos_cardapio_30d: number
  pedidos_whatsapp_30d: number
  cancelados_30d: number
  ultimo_pedido_em: string | null
}

interface PedidoRecente {
  id: number
  id_empresa: number
  nome_empresa: string
  numero_pedido: number
  primeiro_nome: string
  nome_bairro: string
  valor_total: number
  forma_pagamento: string
  status_pedido: string
  origem_pedido: 'cardapio' | 'whatsapp'
  qtd_itens: number
  criado_em: string
}

const ATUALIZAR_A_CADA = 30_000
const JANELA_NOVO = 10 * 60_000

const ESTILO_ORIGEM = {
  whatsapp: 'bg-emerald-50 text-emerald-800',
  cardapio: 'border border-zinc-200 text-zinc-700',
} as const

/** Faixa de números somados de todas as lojas */
export function ResumoUso({ uso, totalLojas }: { uso: UsoLoja[]; totalLojas: number }) {
  if (uso.length === 0) return null
  const soma = (k: keyof UsoLoja) => uso.reduce((t, u) => t + Number(u[k] ?? 0), 0)
  const ativas = uso.filter((u) => u.pedidos_7d > 0).length
  const itens = [
    { rotulo: 'Pedidos hoje', valor: String(soma('pedidos_hoje')) },
    { rotulo: 'Pedidos em 7 dias', valor: String(soma('pedidos_7d')) },
    { rotulo: 'Faturamento 30 dias', valor: formatarMoeda(soma('faturamento_30d')) },
    { rotulo: 'Lojas com pedido em 7 dias', valor: `${ativas} de ${totalLojas}` },
  ]
  return (
    <dl className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
      {itens.map((i) => (
        <div key={i.rotulo} className="cartao px-4 py-3">
          <dt className="text-xs text-zinc-500">{i.rotulo}</dt>
          <dd className="mt-0.5 text-xl font-bold tabular-nums">{i.valor}</dd>
        </div>
      ))}
    </dl>
  )
}

/** Últimos pedidos de todas as lojas, atualizando sozinho */
export function FeedPedidos({ idLoja, aoMudarLoja }: { idLoja: number | null; aoMudarLoja: (id: number | null) => void }) {
  const [pedidos, setPedidos] = useState<PedidoRecente[] | null>(null)
  const [lojas, setLojas] = useState<{ id: number; nome_empresa: string }[]>([])
  const [erro, setErro] = useState<string | null>(null)
  const [atualizadoEm, setAtualizadoEm] = useState<Date | null>(null)
  // pedidos feitos nos últimos 10 minutos ganham destaque
  const [novos, setNovos] = useState<Set<number>>(new Set())

  useEffect(() => {
    supabase.rpc('listar_empresas_admin').then(({ data }) => setLojas((data as { id: number; nome_empresa: string }[]) ?? []))
  }, [])

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.rpc('pedidos_recentes_admin', { p_limite: 100, p_id_empresa: idLoja })
    if (error) return setErro(mensagemErro(error))
    const lista = (data as PedidoRecente[]) ?? []
    setErro(null)
    const corte = Date.now() - JANELA_NOVO
    setNovos(new Set(lista.filter((p) => new Date(p.criado_em).getTime() >= corte).map((p) => p.id)))
    setPedidos(lista)
    setAtualizadoEm(new Date())
  }, [idLoja])

  // trocar de loja remonta o componente (key), então o estado já começa limpo
  useEffect(() => {
    carregar()
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') carregar()
    }, ATUALIZAR_A_CADA)
    const aoVoltar = () => document.visibilityState === 'visible' && carregar()
    document.addEventListener('visibilitychange', aoVoltar)
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', aoVoltar)
    }
  }, [carregar])

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <h1 className="flex-1 text-xl font-bold">Pedidos chegando</h1>
        <select
          className="campo max-w-xs py-2"
          aria-label="Filtrar por loja"
          value={idLoja ?? ''}
          onChange={(e) => aoMudarLoja(e.target.value ? Number(e.target.value) : null)}
        >
          <option value="">Todas as lojas</option>
          {lojas.map((l) => (
            <option key={l.id} value={l.id}>
              {l.nome_empresa}
            </option>
          ))}
        </select>
        <button type="button" className="botao botao-secundario px-3 py-2 text-sm" onClick={carregar}>
          Atualizar
        </button>
      </div>
      <p className="-mt-2 mb-3 text-xs text-zinc-500">
        Atualiza sozinho a cada 30 segundos
        {atualizadoEm ? ` · última vez às ${atualizadoEm.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}` : ''}
      </p>
      {erro && <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{erro}</p>}

      {pedidos === null ? (
        <p className="py-10 text-center text-zinc-500">Carregando...</p>
      ) : pedidos.length === 0 ? (
        <p className="cartao py-10 text-center text-zinc-500">Nenhum pedido ainda.</p>
      ) : (
        <ul className="cartao divide-y divide-zinc-100">
          {pedidos.map((p) => (
            <li key={p.id} className={`flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 text-sm transition-colors ${novos.has(p.id) ? 'bg-amber-50' : ''}`}>
              <div className="min-w-0 basis-full sm:basis-0 sm:flex-1">
                <p className="font-medium">
                  {p.nome_empresa} <span className="text-zinc-500">· #{p.numero_pedido}</span>
                  {novos.has(p.id) && <span className="ml-2 rounded bg-amber-200 px-1.5 py-0.5 text-[11px] font-semibold text-amber-900">novo</span>}
                </p>
                <p className="text-zinc-500">
                  {p.primeiro_nome} · {p.nome_bairro} · {p.qtd_itens} {p.qtd_itens === 1 ? 'item' : 'itens'} ·{' '}
                  {NOMES_PAGAMENTO[p.forma_pagamento] ?? p.forma_pagamento}
                </p>
              </div>
              <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${ESTILO_ORIGEM[p.origem_pedido]}`}>
                {p.origem_pedido === 'whatsapp' ? 'WhatsApp' : 'Cardápio'}
              </span>
              <span className={`text-xs font-medium sm:w-32 ${p.status_pedido === 'cancelado' ? 'text-red-700' : 'text-zinc-700'}`}>
                {NOMES_STATUS[p.status_pedido] ?? p.status_pedido}
              </span>
              <span className="font-semibold tabular-nums sm:w-24 sm:text-right">{formatarMoeda(p.valor_total)}</span>
              <span className="ml-auto text-right text-xs text-zinc-500 tabular-nums sm:ml-0 sm:w-28" title={formatarDataHora(p.criado_em)}>
                {tempoRelativo(p.criado_em)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
