import { Link } from 'react-router-dom'
import { Folha } from '../componentes/Folha'
import { formatarDataHora, formatarMoeda, NOMES_STATUS } from '../lib/formatar'
import type { StatusPedido } from '../lib/tipos'
import { FINALIZADOS, type PedidoComStatus } from './pedidosSalvos'

export function SeloStatus({ status }: { status?: StatusPedido }) {
  if (!status) return null
  const cor =
    status === 'cancelado'
      ? 'bg-red-50 text-red-700'
      : status === 'entregue'
        ? 'bg-zinc-100 text-zinc-600'
        : 'bg-emerald-50 text-emerald-700'
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-semibold ${cor}`}>
      {!FINALIZADOS.includes(status) && (
        <span className="size-1.5 rounded-full bg-current animate-[pulso_1.6s_ease-in-out_infinite]" />
      )}
      {NOMES_STATUS[status]}
    </span>
  )
}

export function FolhaMeusPedidos({
  aberta,
  aoFechar,
  pedidos,
  slugAtual,
}: {
  aberta: boolean
  aoFechar: () => void
  pedidos: PedidoComStatus[]
  slugAtual: string
}) {
  const desta = pedidos.filter((p) => p.slug === slugAtual)
  const outras = pedidos.filter((p) => p.slug !== slugAtual)

  return (
    <Folha aberta={aberta} aoFechar={aoFechar} titulo="Meus pedidos">
      <div className="px-5 pb-6">
        <p className="text-sm text-zinc-500">Pedidos feitos neste celular.</p>
        {pedidos.length === 0 ? (
          <p className="py-10 text-center text-zinc-500">Quando você fizer um pedido, ele aparece aqui.</p>
        ) : (
          <>
            <ListaPedidos pedidos={desta} aoAbrir={aoFechar} />
            {outras.length > 0 && (
              <>
                <h3 className="mt-6 text-xs font-semibold uppercase tracking-wider text-zinc-400">Outras lojas</h3>
                <ListaPedidos pedidos={outras} aoAbrir={aoFechar} mostrarLoja />
              </>
            )}
          </>
        )}
      </div>
    </Folha>
  )
}

function ListaPedidos({
  pedidos,
  aoAbrir,
  mostrarLoja = false,
}: {
  pedidos: PedidoComStatus[]
  aoAbrir: () => void
  mostrarLoja?: boolean
}) {
  if (pedidos.length === 0) return null
  return (
    <ul className="mt-3 space-y-2">
      {pedidos.map((p) => (
        <li key={p.codigo}>
          <Link
            to={`/${p.slug}/pedido/${p.codigo}`}
            onClick={aoAbrir}
            className="flex items-center gap-3 rounded-2xl border border-zinc-200 p-3 transition hover:border-zinc-300 active:scale-[0.99]"
          >
            <span
              className="grid size-11 shrink-0 place-items-center rounded-xl font-mono text-sm font-semibold text-white"
              style={{ background: p.cor_principal }}
            >
              #{p.numero_pedido}
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate font-semibold">
                {mostrarLoja ? p.nome_empresa : `Pedido #${p.numero_pedido}`}
              </span>
              <span className="block text-sm text-zinc-500">
                {formatarDataHora(p.criado_em)} · {formatarMoeda(p.valor_total)}
              </span>
            </span>
            <SeloStatus status={p.status} />
            <svg viewBox="0 0 24 24" className="size-4 shrink-0 text-zinc-400" fill="none" stroke="currentColor" strokeWidth={2.4}>
              <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </Link>
        </li>
      ))}
    </ul>
  )
}
