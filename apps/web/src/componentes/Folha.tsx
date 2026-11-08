import { useEffect, type ReactNode } from 'react'

interface Props {
  aberta: boolean
  aoFechar: () => void
  titulo?: ReactNode
  children: ReactNode
  rodape?: ReactNode
  largura?: 'md' | 'lg'
  /** some com o cabeçalho (o conteúdo traz o próprio, ex.: foto do produto) */
  semCabecalho?: boolean
}

/** Modal que sobe de baixo no celular e fica centralizado no desktop */
export function Folha({ aberta, aoFechar, titulo, children, rodape, largura = 'md', semCabecalho = false }: Props) {
  useEffect(() => {
    if (!aberta) return
    const tecla = (e: KeyboardEvent) => e.key === 'Escape' && aoFechar()
    const overflowAnterior = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    window.addEventListener('keydown', tecla)
    return () => {
      document.body.style.overflow = overflowAnterior
      window.removeEventListener('keydown', tecla)
    }
  }, [aberta, aoFechar])

  if (!aberta) return null

  const botaoFechar = (
    <button
      type="button"
      onClick={aoFechar}
      className={`grid size-9 shrink-0 place-items-center rounded-full transition ${
        semCabecalho
          ? 'absolute right-3 top-3 z-30 bg-white/95 text-zinc-800 shadow-md hover:bg-white'
          : 'text-zinc-500 hover:bg-zinc-100'
      }`}
      aria-label="Fechar"
    >
      <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth={2.2}>
        <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
      </svg>
    </button>
  )

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4">
      <div
        className="absolute inset-0 bg-[rgba(9,9,11,0.55)] animate-[surgir_.18s_ease-out]"
        onClick={aoFechar}
        aria-hidden
      />
      <div
        role="dialog"
        aria-modal="true"
        className={`relative flex max-h-[94dvh] w-full flex-col overflow-clip rounded-t-[28px] bg-white shadow-2xl sm:rounded-3xl ${
          largura === 'lg' ? 'sm:max-w-2xl' : 'sm:max-w-lg'
        } animate-[subir_.26s_cubic-bezier(.2,.9,.3,1)]`}
      >
        <span
          className="pointer-events-none absolute left-1/2 top-2 z-30 h-1 w-10 -translate-x-1/2 rounded-full bg-zinc-300/90 sm:hidden"
          aria-hidden
        />
        {semCabecalho ? (
          botaoFechar
        ) : (
          <div className="flex items-center justify-between gap-3 px-5 pb-2 pt-5">
            <div className="min-w-0 flex-1 font-display text-xl font-extrabold tracking-tight">{titulo}</div>
            {botaoFechar}
          </div>
        )}
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{children}</div>
        {rodape && (
          <div className="border-t border-zinc-100 bg-white p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
            {rodape}
          </div>
        )}
      </div>
    </div>
  )
}

export function Contador({
  valor,
  aoMudar,
  minimo = 0,
  maximo = 99,
  pequeno = false,
}: {
  valor: number
  aoMudar: (v: number) => void
  minimo?: number
  maximo?: number
  pequeno?: boolean
}) {
  const tamanho = pequeno ? 'size-8' : 'size-11'
  return (
    <div className="inline-flex items-center rounded-full bg-zinc-100 p-0.5">
      <button
        type="button"
        className={`${tamanho} grid place-items-center rounded-full text-lg font-semibold text-loja transition hover:bg-white disabled:text-zinc-300 disabled:hover:bg-transparent`}
        onClick={() => aoMudar(valor - 1)}
        disabled={valor <= minimo}
        aria-label="Diminuir"
      >
        −
      </button>
      <span className="min-w-7 text-center text-sm font-bold tabular-nums">{valor}</span>
      <button
        type="button"
        className={`${tamanho} grid place-items-center rounded-full text-lg font-semibold text-loja transition hover:bg-white disabled:text-zinc-300 disabled:hover:bg-transparent`}
        onClick={() => aoMudar(valor + 1)}
        disabled={valor >= maximo}
        aria-label="Aumentar"
      >
        +
      </button>
    </div>
  )
}
