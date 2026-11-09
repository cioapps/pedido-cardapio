import { useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { estiloLoja } from '../lib/corLoja'
import { formatarMoeda, linkWhatsApp, NOMES_STATUS } from '../lib/formatar'
import { mensagemErro, supabase } from '../lib/supabase'
import type { Cardapio, EmpresaCardapio, ProdutoCardapio } from '../lib/tipos'
import { useCarrinho } from './carrinho'
import { Checkout } from './Checkout'
import { FolhaMeusPedidos } from './MeusPedidos'
import { pedidoEmAndamento, usePedidosSalvos } from './pedidosSalvos'
import { ModalProduto } from './ModalProduto'

export function PaginaCardapio() {
  const { slug = '' } = useParams()
  const [cardapio, setCardapio] = useState<Cardapio | null>(null)
  const [estado, setEstado] = useState<'carregando' | 'ok' | 'nao_encontrado' | 'erro'>('carregando')
  const [erro, setErro] = useState('')

  useEffect(() => {
    let cancelado = false
    const carregar = async () => {
      const { data, error } = await supabase.rpc('obter_cardapio', { p_slug: slug })
      if (cancelado) return
      if (error) {
        setErro(mensagemErro(error))
        setEstado('erro')
      } else if (!data) {
        setEstado('nao_encontrado')
      } else {
        setCardapio(data as Cardapio)
        setEstado('ok')
        document.title = `${(data as Cardapio).empresa.nome_empresa} · Cardápio`
      }
    }
    carregar()
    // atualiza status aberto/fechado de tempos em tempos
    const intervalo = window.setInterval(carregar, 120_000)
    return () => {
      cancelado = true
      window.clearInterval(intervalo)
    }
  }, [slug])

  if (estado === 'carregando') {
    return (
      <div className="mx-auto max-w-2xl animate-pulse">
        <div className="h-44 bg-zinc-200 sm:rounded-b-3xl" />
        <div className="space-y-3 p-4">
          <div className="h-12 rounded-xl bg-zinc-200" />
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="h-24 rounded-2xl bg-zinc-200" />
          ))}
        </div>
      </div>
    )
  }

  if (estado !== 'ok' || !cardapio) {
    return (
      <div className="grid min-h-dvh place-items-center p-6 text-center">
        <div>
          <p className="font-display text-2xl font-extrabold">
            {estado === 'nao_encontrado' ? 'Loja não encontrada' : 'Não foi possível abrir o cardápio'}
          </p>
          <p className="mt-2 text-zinc-500">
            {estado === 'nao_encontrado' ? 'Confira o link que você recebeu.' : erro}
          </p>
          {estado === 'erro' && (
            <button type="button" className="botao botao-secundario mt-6" onClick={() => window.location.reload()}>
              Tentar de novo
            </button>
          )}
        </div>
      </div>
    )
  }

  if (cardapio.empresa.loja_disponivel === false) return <Indisponivel empresa={cardapio.empresa} />
  if (!cardapio.empresa.cardapio_ativo) return <SoWhatsapp empresa={cardapio.empresa} />

  return <ConteudoCardapio cardapio={cardapio} />
}

function Logo({ empresa, tamanho = 'size-16' }: { empresa: EmpresaCardapio; tamanho?: string }) {
  return empresa.logo_url ? (
    <img
      src={empresa.logo_url}
      alt=""
      className={`${tamanho} shrink-0 rounded-2xl bg-white object-cover shadow-sm ring-1 ring-black/5`}
    />
  ) : (
    <div
      className={`${tamanho} grid shrink-0 place-items-center rounded-2xl bg-white font-display text-3xl font-extrabold text-loja shadow-sm`}
    >
      {empresa.nome_empresa.charAt(0)}
    </div>
  )
}

/** Assinatura da loja vencida ou bloqueada: não mostra o cardápio nem aceita pedido */
function Indisponivel({ empresa }: { empresa: EmpresaCardapio }) {
  return (
    <div style={estiloLoja(empresa.cor_principal)} className="grid min-h-dvh place-items-center p-6 text-center">
      <div className="max-w-sm">
        <div className="mx-auto mb-4 w-fit">
          <Logo empresa={empresa} tamanho="size-20" />
        </div>
        <h1 className="font-display text-3xl font-extrabold tracking-tight">{empresa.nome_empresa}</h1>
        <p className="mt-2 text-zinc-600">O cardápio online desta loja está indisponível no momento.</p>
      </div>
    </div>
  )
}

/** Loja que atende só pelo WhatsApp (módulo de cardápio desligado) */
function SoWhatsapp({ empresa }: { empresa: EmpresaCardapio }) {
  return (
    <div style={estiloLoja(empresa.cor_principal)} className="grid min-h-dvh place-items-center p-6 text-center">
      <div className="max-w-sm">
        <div className="mx-auto mb-4 w-fit">
          <Logo empresa={empresa} tamanho="size-20" />
        </div>
        <h1 className="font-display text-3xl font-extrabold tracking-tight">{empresa.nome_empresa}</h1>
        <p className="mt-2 text-zinc-600">Os pedidos desta loja são feitos pelo WhatsApp.</p>
        {empresa.telefone_whatsapp && (
          <a
            className="botao-loja mt-6 w-full"
            href={linkWhatsApp(empresa.telefone_whatsapp, 'Olá! Quero fazer um pedido.')}
          >
            Pedir pelo WhatsApp
          </a>
        )}
      </div>
    </div>
  )
}

const temPrecoVariavel = (p: ProdutoCardapio) =>
  p.grupos.some((g) => g.minimo_selecao > 0 && g.opcoes.some((o) => Number(o.preco_adicional) > 0))

function ConteudoCardapio({ cardapio }: { cardapio: Cardapio }) {
  const { empresa, categorias, horarios } = cardapio
  const carrinho = useCarrinho(empresa.slug_empresa)
  const pedidos = usePedidosSalvos(empresa.slug_empresa)
  const [produtoAberto, setProdutoAberto] = useState<ProdutoCardapio | null>(null)
  const [checkoutAberto, setCheckoutAberto] = useState(false)
  const [pedidosAberto, setPedidosAberto] = useState(false)
  const [busca, setBusca] = useState('')
  const [categoriaAtiva, setCategoriaAtiva] = useState<number | null>(categorias[0]?.id ?? null)
  const [adicionado, setAdicionado] = useState(0)

  const emAndamento = pedidos.filter(pedidoEmAndamento)

  const categoriasFiltradas = useMemo(() => {
    const termo = busca.trim().toLowerCase()
    if (!termo) return categorias
    return categorias
      .map((c) => ({
        ...c,
        produtos: c.produtos.filter(
          (p) =>
            p.nome_produto.toLowerCase().includes(termo) ||
            p.descricao_produto?.toLowerCase().includes(termo),
        ),
      }))
      .filter((c) => c.produtos.length > 0)
  }, [busca, categorias])

  // Destaca a categoria visível ao rolar
  useEffect(() => {
    const observador = new IntersectionObserver(
      (entradas) => {
        const visivel = entradas.find((e) => e.isIntersecting)
        if (visivel) setCategoriaAtiva(Number(visivel.target.getAttribute('data-categoria')))
      },
      { rootMargin: '-130px 0px -65% 0px' },
    )
    document.querySelectorAll('[data-categoria]').forEach((el) => observador.observe(el))
    return () => observador.disconnect()
  }, [categoriasFiltradas])

  useEffect(() => {
    document.getElementById(`aba-${categoriaAtiva}`)?.scrollIntoView({ inline: 'center', block: 'nearest' })
  }, [categoriaAtiva])

  const irParaCategoria = (id: number) => {
    const alvo = document.getElementById(`categoria-${id}`)
    if (alvo) window.scrollTo({ top: alvo.getBoundingClientRect().top + window.scrollY - 118, behavior: 'smooth' })
  }

  const hoje = new Date().getDay()
  const horariosHoje = horarios.filter((h) => h.dia_semana === hoje)
  const textoHorario = horariosHoje.map((h) => `${h.hora_abertura}–${h.hora_fechamento}`).join(', ')

  return (
    <div style={estiloLoja(empresa.cor_principal)} className="min-h-dvh pb-32">
      <header className="bg-loja text-[var(--sobre-loja)]">
        <div className="mx-auto max-w-2xl px-4 pb-10 pt-5">
          <div className="flex items-start justify-between gap-3">
            <Logo empresa={empresa} />
            {pedidos.length > 0 && (
              <button
                type="button"
                onClick={() => setPedidosAberto(true)}
                className="inline-flex items-center gap-2 rounded-full bg-black/15 px-3.5 py-2 text-sm font-semibold backdrop-blur transition hover:bg-black/25"
              >
                <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth={2.2}>
                  <path d="M7 3h10v18l-2.5-1.5L12 21l-2.5-1.5L7 21z" strokeLinejoin="round" />
                  <path d="M10 8h4M10 12h4" strokeLinecap="round" />
                </svg>
                Meus pedidos
                {emAndamento.length > 0 && (
                  <span className="size-2 rounded-full bg-emerald-400 animate-[pulso_1.6s_ease-in-out_infinite]" />
                )}
              </button>
            )}
          </div>
          <h1 className="mt-4 font-display text-[2rem] font-extrabold leading-[1.05] tracking-tight">
            {empresa.nome_empresa}
          </h1>
          {empresa.endereco_empresa && <p className="mt-1.5 text-sm opacity-80">{empresa.endereco_empresa}</p>}
        </div>
      </header>

      <div className="mx-auto -mt-6 max-w-2xl px-4">
        <div className="cartao grid grid-cols-3 divide-x divide-zinc-100 py-3 text-center shadow-[0_10px_30px_-12px_rgba(0,0,0,.18)]">
          <div className="px-2">
            <p
              className={`inline-flex items-center gap-1.5 text-sm font-bold ${
                empresa.loja_aberta ? 'text-emerald-700' : 'text-red-600'
              }`}
            >
              <span className={`size-2 rounded-full ${empresa.loja_aberta ? 'bg-emerald-500' : 'bg-red-500'}`} />
              {empresa.loja_aberta ? 'Aberto' : 'Fechado'}
            </p>
            <p className="mt-0.5 truncate text-xs text-zinc-500">{textoHorario ? `Hoje ${textoHorario}` : 'agora'}</p>
          </div>
          <div className="px-2">
            <p className="text-sm font-bold">{empresa.tempo_entrega_minutos} min</p>
            <p className="mt-0.5 text-xs text-zinc-500">entrega</p>
          </div>
          <div className="px-2">
            <p className="text-sm font-bold">
              {Number(empresa.pedido_minimo) > 0 ? formatarMoeda(empresa.pedido_minimo) : 'Sem mínimo'}
            </p>
            <p className="mt-0.5 text-xs text-zinc-500">pedido mínimo</p>
          </div>
        </div>

        {!empresa.loja_aberta && (
          <p className="mt-3 rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900">
            A loja está fechada agora. Dá para olhar o cardápio, mas os pedidos estão pausados.
          </p>
        )}

        {emAndamento.map((p) => (
          <Link
            key={p.codigo}
            to={`/${p.slug}/pedido/${p.codigo}`}
            className="mt-3 flex items-center gap-3 rounded-2xl bg-zinc-900 px-4 py-3 text-white transition active:scale-[0.99]"
          >
            <span className="relative grid size-9 shrink-0 place-items-center rounded-full bg-white/10">
              <span className="absolute inset-0 rounded-full border-2 border-emerald-400/70 animate-[pulso_1.6s_ease-in-out_infinite]" />
              <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth={2.2}>
                <circle cx="12" cy="12" r="8" />
                <path d="M12 8v4l2.5 2" strokeLinecap="round" />
              </svg>
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold">
                Pedido #{p.numero_pedido} · {p.status ? NOMES_STATUS[p.status] : ''}
              </span>
              <span className="block text-xs text-white/60">Toque para acompanhar</span>
            </span>
            <svg viewBox="0 0 24 24" className="size-4 text-white/60" fill="none" stroke="currentColor" strokeWidth={2.4}>
              <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </Link>
        ))}
      </div>

      <div className="sticky top-0 z-30 mt-4 bg-[var(--fundo)]/95 backdrop-blur">
        <div className="mx-auto max-w-2xl px-4 pt-3">
          <label className="relative block">
            <span className="sr-only">Buscar no cardápio</span>
            <svg
              viewBox="0 0 24 24"
              className="pointer-events-none absolute left-3.5 top-1/2 size-[18px] -translate-y-1/2 text-zinc-400"
              fill="none"
              stroke="currentColor"
              strokeWidth={2.2}
            >
              <circle cx="11" cy="11" r="7" />
              <path d="M20 20l-3.5-3.5" strokeLinecap="round" />
            </svg>
            <input
              type="search"
              className="campo border-transparent bg-white py-2.5 pl-10 shadow-sm"
              placeholder="Buscar lanche, bebida..."
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
            />
          </label>
        </div>
        <nav className="mx-auto flex max-w-2xl gap-1.5 overflow-x-auto px-4 py-2.5 [scrollbar-width:none]">
          {categoriasFiltradas.map((c) => (
            <button
              key={c.id}
              id={`aba-${c.id}`}
              type="button"
              onClick={() => irParaCategoria(c.id)}
              className={`shrink-0 rounded-full px-4 py-1.5 text-sm font-semibold transition ${
                categoriaAtiva === c.id
                  ? 'bg-zinc-900 text-white'
                  : 'bg-white text-zinc-600 shadow-sm hover:text-zinc-900'
              }`}
            >
              {c.nome_categoria}
            </button>
          ))}
        </nav>
      </div>

      <main className="mx-auto max-w-2xl px-4">
        {categoriasFiltradas.length === 0 && (
          <p className="py-16 text-center text-zinc-500">
            {busca ? `Nada encontrado para "${busca}".` : 'O cardápio ainda está sendo montado.'}
          </p>
        )}
        {categoriasFiltradas.map((c) => (
          <section key={c.id} id={`categoria-${c.id}`} data-categoria={c.id} className="pt-5">
            <h2 className="mb-2.5 flex items-baseline gap-2 px-1 font-display text-xl font-extrabold tracking-tight">
              {c.nome_categoria}
              <span className="font-sans text-sm font-medium text-zinc-400">{c.produtos.length}</span>
            </h2>
            <ul className="cartao divide-y divide-zinc-100 overflow-clip">
              {c.produtos.map((p) => (
                <li key={p.id}>
                  <button
                    type="button"
                    onClick={() => setProdutoAberto(p)}
                    className="group flex w-full gap-3 p-4 text-left transition hover:bg-zinc-50 active:bg-zinc-100"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="font-semibold leading-snug">{p.nome_produto}</p>
                      {p.descricao_produto && (
                        <p className="mt-1 line-clamp-2 text-sm leading-snug text-zinc-500">{p.descricao_produto}</p>
                      )}
                      <p className="mt-2 text-[15px] font-bold tabular-nums">
                        {temPrecoVariavel(p) && (
                          <span className="mr-1 text-xs font-medium text-zinc-500">a partir de</span>
                        )}
                        {formatarMoeda(p.preco_produto)}
                      </p>
                    </div>
                    <div className="relative shrink-0 self-center">
                      {p.foto_url ? (
                        <img
                          src={p.foto_url}
                          alt=""
                          loading="lazy"
                          className="size-24 rounded-xl bg-zinc-100 object-cover"
                        />
                      ) : (
                        <span className="block size-10" />
                      )}
                      <span
                        className={`absolute grid size-8 place-items-center rounded-full bg-white text-loja shadow-md ring-1 ring-black/5 transition group-hover:scale-110 ${
                          p.foto_url ? '-bottom-1.5 -right-1.5' : 'bottom-1 right-0'
                        }`}
                        aria-hidden
                      >
                        <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth={3}>
                          <path d="M12 5v14M5 12h14" strokeLinecap="round" />
                        </svg>
                      </span>
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))}

        {empresa.telefone_whatsapp && (
          <p className="py-10 text-center text-sm text-zinc-500">
            Ficou com dúvida?{' '}
            <a className="font-semibold text-loja-escura underline underline-offset-2" href={linkWhatsApp(empresa.telefone_whatsapp)}>
              Chame a loja no WhatsApp
            </a>
          </p>
        )}
      </main>

      {carrinho.quantidadeTotal > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-40 px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-6 [background:linear-gradient(to_top,var(--fundo)_55%,transparent)]">
          <button
            key={adicionado}
            type="button"
            onClick={() => setCheckoutAberto(true)}
            className="botao-loja mx-auto flex w-full max-w-2xl justify-between rounded-2xl py-3.5 pl-3 pr-4 text-[var(--sobre-loja)] animate-[subir_.3s_cubic-bezier(.2,.9,.3,1)]"
          >
            <span className="flex items-center gap-2.5">
              <span className="grid h-8 min-w-8 place-items-center rounded-lg bg-black/20 px-1.5 text-sm tabular-nums">
                {carrinho.quantidadeTotal}
              </span>
              Ver sacola
            </span>
            <span className="tabular-nums">{formatarMoeda(carrinho.subtotal)}</span>
          </button>
        </div>
      )}

      <ModalProduto
        produto={produtoAberto}
        lojaAberta={empresa.loja_aberta}
        aoFechar={() => setProdutoAberto(null)}
        aoAdicionar={(item) => {
          carrinho.adicionar(item)
          setAdicionado((n) => n + 1)
        }}
      />
      <Checkout
        aberto={checkoutAberto}
        aoFechar={() => setCheckoutAberto(false)}
        cardapio={cardapio}
        carrinho={carrinho}
      />
      <FolhaMeusPedidos
        aberta={pedidosAberto}
        aoFechar={() => setPedidosAberto(false)}
        pedidos={pedidos}
      />
    </div>
  )
}
