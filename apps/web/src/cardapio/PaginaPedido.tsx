import { useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { estiloLoja } from '../lib/corLoja'
import { formatarDataHora, formatarHora, formatarMoeda, linkWhatsApp, NOMES_PAGAMENTO } from '../lib/formatar'
import { supabase } from '../lib/supabase'
import type { StatusPedido } from '../lib/tipos'

interface PedidoConsulta {
  numero_pedido: number
  status_pedido: StatusPedido
  criado_em: string
  nome_cliente: string
  nome_bairro: string
  forma_pagamento: string
  troco_para: number | null
  subtotal: number
  taxa_entrega: number
  valor_total: number
  nome_empresa: string
  telefone_whatsapp: string | null
  cor_principal: string
  itens: {
    nome_produto: string
    quantidade: number
    valor_total_item: number
    observacao_item: string | null
    opcoes: { nome_grupo: string; nome_opcao: string; quantidade: number }[]
  }[]
}

const ETAPAS: { status: StatusPedido; nome: string; agora: string; descricao: string }[] = [
  { status: 'novo', nome: 'Enviado', agora: 'Pedido enviado', descricao: 'Esperando a loja confirmar.' },
  { status: 'aceito', nome: 'Aceito', agora: 'Pedido aceito', descricao: 'A loja confirmou e já vai começar.' },
  { status: 'em_preparo', nome: 'Preparo', agora: 'Em preparo', descricao: 'Seu pedido está sendo feito agora.' },
  { status: 'saiu_entrega', nome: 'A caminho', agora: 'Saiu para entrega', descricao: 'O entregador já está indo até você.' },
  { status: 'entregue', nome: 'Entregue', agora: 'Entregue', descricao: 'Bom apetite!' },
]

export function PaginaPedido() {
  const { slug = '', codigo = '' } = useParams()
  const [parametros] = useSearchParams()
  const acabouDeFazer = parametros.get('novo') === '1'
  const [pedido, setPedido] = useState<PedidoConsulta | null>(null)
  const [carregando, setCarregando] = useState(true)

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [codigo])

  useEffect(() => {
    let cancelado = false
    let intervalo = 0
    const carregar = async () => {
      const { data } = await supabase.rpc('consultar_pedido', { p_codigo: codigo })
      if (cancelado) return
      setPedido((data as PedidoConsulta) ?? null)
      setCarregando(false)
      const finalizado = data && ['entregue', 'cancelado'].includes((data as PedidoConsulta).status_pedido)
      if (finalizado) window.clearInterval(intervalo)
    }
    carregar()
    intervalo = window.setInterval(carregar, 15_000)
    return () => {
      cancelado = true
      window.clearInterval(intervalo)
    }
  }, [codigo])

  useEffect(() => {
    if (pedido) document.title = `Pedido #${pedido.numero_pedido} · ${pedido.nome_empresa}`
  }, [pedido])

  if (carregando)
    return (
      <div className="mx-auto max-w-md animate-pulse space-y-4 p-4 pt-10">
        <div className="h-40 rounded-3xl bg-zinc-200" />
        <div className="h-72 rounded-lg bg-zinc-200" />
      </div>
    )

  if (!pedido)
    return (
      <div className="grid min-h-dvh place-items-center p-6 text-center">
        <div>
          <p className="font-display text-2xl font-extrabold">Pedido não encontrado</p>
          <p className="mt-2 text-zinc-500">Confira se o link está completo.</p>
          <Link className="botao botao-secundario mt-6" to={`/${slug}`}>
            Voltar ao cardápio
          </Link>
        </div>
      </div>
    )

  const indiceAtual = ETAPAS.findIndex((e) => e.status === pedido.status_pedido)
  const cancelado = pedido.status_pedido === 'cancelado'
  const etapa = ETAPAS[indiceAtual]
  const finalizado = cancelado || pedido.status_pedido === 'entregue'

  return (
    <div style={estiloLoja(pedido.cor_principal)} className="min-h-dvh pb-10">
      <header className="bg-loja text-[var(--sobre-loja)]">
        <div className="mx-auto flex max-w-md items-center gap-2 px-3 pb-16 pt-3">
          <Link
            to={`/${slug}`}
            className="inline-flex items-center gap-1 rounded-full px-2.5 py-1.5 text-sm font-semibold transition hover:bg-black/10"
          >
            <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth={2.6}>
              <path d="M15 6l-6 6 6 6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            {pedido.nome_empresa}
          </Link>
        </div>
      </header>

      <main className="mx-auto -mt-14 max-w-md space-y-5 px-4">
        {/* Situação agora */}
        <section className="cartao p-5 shadow-[0_14px_40px_-16px_rgba(0,0,0,.25)]">
          {acabouDeFazer && pedido.status_pedido === 'novo' && (
            <p className="mb-3 inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700">
              <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="currentColor" strokeWidth={3.5}>
                <path d="M5 12.5l4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Pedido recebido pela loja
            </p>
          )}
          {cancelado ? (
            <>
              <h1 className="font-display text-3xl font-extrabold tracking-tight text-red-600">Pedido cancelado</h1>
              <p className="mt-1 text-zinc-600">Fale com a loja para saber o que aconteceu.</p>
            </>
          ) : (
            <>
              <p className="text-xs font-semibold uppercase tracking-wider text-zinc-400">
                Pedido #{pedido.numero_pedido} · feito às {formatarHora(pedido.criado_em)}
              </p>
              <h1 className="mt-1 font-display text-[2rem] font-extrabold leading-tight tracking-tight">
                {etapa?.agora}
              </h1>
              <p className="mt-0.5 text-zinc-600">{etapa?.descricao}</p>

              <ol className="mt-5 grid grid-cols-5 gap-1.5" aria-label="Andamento do pedido">
                {ETAPAS.map((e, i) => {
                  const feito = i <= indiceAtual
                  const atual = i === indiceAtual && !finalizado
                  return (
                    <li key={e.status} aria-current={i === indiceAtual ? 'step' : undefined}>
                      <span
                        className={`block h-1.5 rounded-full ${feito ? 'bg-loja' : 'bg-zinc-200'} ${
                          atual ? 'animate-[pulso_1.6s_ease-in-out_infinite]' : ''
                        }`}
                      />
                      <span
                        className={`mt-1.5 block text-[11px] leading-tight ${
                          i === indiceAtual ? 'font-bold text-zinc-900' : feito ? 'text-zinc-600' : 'text-zinc-400'
                        }`}
                      >
                        {e.nome}
                      </span>
                    </li>
                  )
                })}
              </ol>
            </>
          )}
          {!finalizado && (
            <p className="mt-4 flex items-center gap-1.5 text-xs text-zinc-400">
              <span className="size-1.5 rounded-full bg-emerald-500 animate-[pulso_1.6s_ease-in-out_infinite]" />
              Atualiza sozinho
            </p>
          )}
        </section>

        {/* Comanda: o mesmo cupom que sai na impressora da cozinha */}
        <section aria-label="Resumo do pedido">
          <div className="relative z-10 mx-1 h-3 rounded-full bg-zinc-800 shadow-inner" aria-hidden />
          <div
            className={`picote relative mx-3 -mt-1.5 bg-white px-5 pb-7 pt-6 font-mono text-[13px] leading-relaxed text-zinc-800 shadow-sm ${
              acabouDeFazer ? 'animate-[imprimir_1.1s_steps(14)_both]' : ''
            }`}
          >
            <p className="text-center text-sm font-semibold uppercase tracking-wide">{pedido.nome_empresa}</p>
            <p className="text-center text-zinc-500">{formatarDataHora(pedido.criado_em)}</p>
            <p className="my-3 text-center text-2xl font-semibold">#{pedido.numero_pedido}</p>
            <Tracejado />
            <ul className="space-y-2.5 py-1">
              {pedido.itens.map((item, i) => (
                <li key={i}>
                  <div className="flex justify-between gap-3">
                    <span className="font-semibold">
                      {item.quantidade}x {item.nome_produto}
                    </span>
                    <span className="shrink-0 tabular-nums">{formatarMoeda(item.valor_total_item)}</span>
                  </div>
                  {item.opcoes.map((o, j) => (
                    <p key={j} className="pl-4 text-zinc-500">
                      + {o.quantidade > 1 ? `${o.quantidade}x ` : ''}
                      {o.nome_opcao}
                    </p>
                  ))}
                  {item.observacao_item && <p className="pl-4 text-zinc-500">obs: {item.observacao_item}</p>}
                </li>
              ))}
            </ul>
            <Tracejado />
            <dl className="space-y-0.5">
              <Linha rotulo="Produtos" valor={formatarMoeda(pedido.subtotal)} />
              <Linha
                rotulo={`Entrega ${pedido.nome_bairro}`}
                valor={Number(pedido.taxa_entrega) > 0 ? formatarMoeda(pedido.taxa_entrega) : 'grátis'}
              />
              <div className="flex justify-between pt-1 text-base font-semibold">
                <dt>TOTAL</dt>
                <dd className="tabular-nums">{formatarMoeda(pedido.valor_total)}</dd>
              </div>
            </dl>
            <Tracejado />
            <p>
              Pagamento: {NOMES_PAGAMENTO[pedido.forma_pagamento]}
              {pedido.troco_para ? ` · troco p/ ${formatarMoeda(pedido.troco_para)}` : ''}
            </p>
            <p>Cliente: {pedido.nome_cliente}</p>
          </div>
        </section>

        <div className="flex flex-col gap-2">
          {pedido.telefone_whatsapp && (
            <a
              className="botao-loja py-3.5"
              href={linkWhatsApp(pedido.telefone_whatsapp, `Olá! Sobre o meu pedido #${pedido.numero_pedido}`)}
            >
              <svg viewBox="0 0 24 24" className="size-5" fill="currentColor" aria-hidden>
                <path d="M12 2a10 10 0 00-8.6 15.1L2 22l5-1.3A10 10 0 1012 2zm0 18.2a8.2 8.2 0 01-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1112 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 01-3.3-2.9c-.3-.4.3-.4.7-1.4.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 00-.7.3 3 3 0 00-.9 2.2 5.2 5.2 0 001.1 2.7 11.8 11.8 0 004.5 4c1.7.7 2.3.8 3.2.6a2.7 2.7 0 001.8-1.2 2.2 2.2 0 00.1-1.2c0-.2-.2-.2-.4-.3z" />
              </svg>
              Falar com a loja
            </a>
          )}
          <Link className="botao botao-secundario py-3.5" to={`/${slug}`}>
            {finalizado ? 'Fazer outro pedido' : 'Voltar ao cardápio'}
          </Link>
        </div>
      </main>
    </div>
  )
}

function Tracejado() {
  return <div className="my-3 border-t border-dashed border-zinc-300" aria-hidden />
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex justify-between gap-3 text-zinc-600">
      <dt className="truncate">{rotulo}</dt>
      <dd className="shrink-0 tabular-nums">{valor}</dd>
    </div>
  )
}
