import type { Session } from '@supabase/supabase-js'
import { useCallback, useEffect, useState } from 'react'
import { formatarDataHora, formatarMoeda, formatarTelefone } from '../lib/formatar'
import { mensagemErro, supabase } from '../lib/supabase'
import { Entrar, Interruptor } from './Entrar'
import { desdeUltimoPedido } from './tempo'
import { FeedPedidos, ResumoUso, type UsoLoja } from './Uso'

interface LojaAdmin {
  id: number
  nome_empresa: string
  slug_empresa: string
  telefone_whatsapp: string | null
  ativo: boolean
  modulo_cardapio_ativo: boolean
  modulo_whatsapp_ativo: boolean
  status_conexao: string | null
  criado_em: string
  situacao_assinatura: 'teste' | 'ativa' | 'bloqueada'
  assinatura_valida_ate: string | null
  assinatura_liberada: boolean
  email_dono: string | null
}

const DIA = 86_400_000

/** Texto curto da assinatura: "Teste · faltam 3 dias", "Ativa até 10/12", "Vencida" */
function resumoAssinatura(l: LojaAdmin) {
  const fim = l.assinatura_valida_ate ? new Date(l.assinatura_valida_ate) : null
  if (l.situacao_assinatura === 'bloqueada') return 'Bloqueada'
  if (fim && fim.getTime() <= Date.now()) return l.situacao_assinatura === 'teste' ? 'Teste vencido' : 'Vencida'
  const nome = l.situacao_assinatura === 'teste' ? 'Teste' : 'Ativa'
  if (!fim) return `${nome} · sem prazo`
  const dias = Math.ceil((fim.getTime() - Date.now()) / DIA)
  return `${nome} até ${fim.toLocaleDateString('pt-BR')} (${dias} ${dias === 1 ? 'dia' : 'dias'})`
}

/** Área do administrador do sistema: liga/desliga os módulos de cada loja */
export default function PaginaAdmin() {
  const [sessao, setSessao] = useState<Session | null | undefined>(undefined)
  const [administrador, setAdministrador] = useState<boolean | null>(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSessao(data.session))
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSessao(s))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!sessao) return
    supabase.rpc('e_administrador').then(({ data }) => setAdministrador(Boolean(data)))
  }, [sessao])

  if (sessao === undefined || (sessao && administrador === null)) {
    return <p className="p-10 text-center text-zinc-500">Carregando...</p>
  }
  if (!sessao) return <Entrar />
  if (!administrador) {
    return (
      <div className="p-10 text-center">
        <p className="text-lg font-semibold">Acesso restrito</p>
        <p className="mt-1 text-zinc-500">Esta conta não é administradora do sistema.</p>
        <button type="button" className="botao botao-secundario mt-4" onClick={() => supabase.auth.signOut()}>
          Sair
        </button>
      </div>
    )
  }
  return <Painel />
}

type Aba = 'lojas' | 'pedidos'

function Painel() {
  const [aba, setAba] = useState<Aba>('lojas')
  const [lojaFeed, setLojaFeed] = useState<number | null>(null)
  const verPedidos = (id: number) => {
    setLojaFeed(id)
    setAba('pedidos')
  }
  return (
    <div className="mx-auto max-w-6xl px-4 py-6">
      <div className="mb-5 flex items-center gap-3">
        <nav className="flex flex-1 gap-1" aria-label="Seções">
          {(['lojas', 'pedidos'] as const).map((a) => (
            <button
              key={a}
              type="button"
              aria-current={aba === a ? 'page' : undefined}
              className={`rounded-lg px-3 py-1.5 text-sm font-semibold transition ${aba === a ? 'bg-zinc-900 text-white' : 'text-zinc-600 hover:bg-zinc-100'}`}
              onClick={() => setAba(a)}
            >
              {a === 'lojas' ? 'Lojas' : 'Pedidos chegando'}
            </button>
          ))}
        </nav>
        <button type="button" className="botao botao-secundario px-3 py-1.5 text-sm" onClick={() => supabase.auth.signOut()}>
          Sair
        </button>
      </div>
      {aba === 'lojas' ? <ListaLojas aoVerPedidos={verPedidos} /> : <FeedPedidos key={lojaFeed ?? 'todas'} idLoja={lojaFeed} aoMudarLoja={setLojaFeed} />}
    </div>
  )
}

function ListaLojas({ aoVerPedidos }: { aoVerPedidos: (id: number) => void }) {
  const [lojas, setLojas] = useState<LojaAdmin[]>([])
  const [uso, setUso] = useState<Map<number, UsoLoja>>(new Map())
  const [busca, setBusca] = useState('')
  const [erro, setErro] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    const [r, u] = await Promise.all([supabase.rpc('listar_empresas_admin'), supabase.rpc('uso_empresas_admin')])
    if (r.error) return setErro(mensagemErro(r.error))
    setLojas((r.data as LojaAdmin[]) ?? [])
    // se a função de uso falhar, a lista de lojas continua funcionando
    if (!u.error) setUso(new Map(((u.data as UsoLoja[]) ?? []).map((x) => [Number(x.id_empresa), x])))
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  const definir = async (loja: LojaAdmin, cardapio: boolean, whatsapp: boolean) => {
    setLojas((l) => l.map((x) => (x.id === loja.id ? { ...x, modulo_cardapio_ativo: cardapio, modulo_whatsapp_ativo: whatsapp } : x)))
    const { error } = await supabase.rpc('definir_modulos_empresa', {
      p_id_empresa: loja.id,
      p_modulo_cardapio: cardapio,
      p_modulo_whatsapp: whatsapp,
    })
    if (error) {
      setErro(mensagemErro(error))
      carregar()
    }
  }

  const assinatura = async (loja: LojaAdmin, situacao: LojaAdmin['situacao_assinatura'], dias: number | null) => {
    // soma a partir do fim atual se ainda estiver valendo (ex.: renovar antes de vencer)
    const fimAtual = loja.assinatura_valida_ate ? new Date(loja.assinatura_valida_ate).getTime() : 0
    const base = situacao !== 'bloqueada' && loja.assinatura_liberada && fimAtual > Date.now() ? fimAtual : Date.now()
    const validaAte = dias === null ? null : new Date(base + dias * DIA).toISOString()
    setErro(null)
    const { error } = await supabase.rpc('definir_assinatura_empresa', {
      p_id_empresa: loja.id,
      p_situacao: situacao,
      p_valida_ate: situacao === 'bloqueada' ? loja.assinatura_valida_ate : validaAte,
    })
    if (error) setErro(mensagemErro(error))
    carregar()
  }

  const termo = busca.trim().toLowerCase()
  const visiveis = lojas.filter(
    (l) =>
      !termo ||
      l.nome_empresa.toLowerCase().includes(termo) ||
      l.slug_empresa.includes(termo) ||
      (l.email_dono ?? '').toLowerCase().includes(termo),
  )

  return (
    <div>
      <ResumoUso uso={[...uso.values()]} totalLojas={lojas.length} />
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <h1 className="flex-1 text-xl font-bold">Lojas ({lojas.length})</h1>
        <input className="campo max-w-xs" placeholder="Buscar loja ou e-mail" value={busca} onChange={(e) => setBusca(e.target.value)} />
      </div>
      {erro && <p className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{erro}</p>}

      <div className="cartao overflow-x-auto">
        <table className="w-full min-w-[1040px] text-left text-sm">
          <thead className="border-b border-zinc-200 bg-zinc-50 text-zinc-600">
            <tr>
              <th className="px-3 py-2 font-medium">Loja</th>
              <th className="px-3 py-2 font-medium">Uso</th>
              <th className="px-3 py-2 font-medium">Assinatura</th>
              <th className="px-3 py-2 text-center font-medium">Cardápio online</th>
              <th className="px-3 py-2 text-center font-medium">WhatsApp com IA</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-100">
            {visiveis.map((l) => (
              <tr key={l.id}>
                <td className="px-3 py-2.5">
                  <p className="font-medium">{l.nome_empresa}</p>
                  <p className="text-zinc-500">
                    /{l.slug_empresa}
                    {l.telefone_whatsapp ? ` · ${formatarTelefone(l.telefone_whatsapp)}` : ''}
                  </p>
                  <p className="text-xs text-zinc-500">
                    {l.email_dono ?? 'sem dono'} · criada {formatarDataHora(l.criado_em)}
                  </p>
                </td>
                <td className="px-3 py-2.5">
                  <CelulaUso uso={uso.get(l.id)} aoVerPedidos={() => aoVerPedidos(l.id)} />
                </td>
                <td className="px-3 py-2.5">
                  <p className={`font-medium ${l.assinatura_liberada ? 'text-emerald-700' : 'text-red-700'}`}>
                    {resumoAssinatura(l)}
                  </p>
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    <button type="button" className="botao botao-secundario px-2 py-1 text-xs" onClick={() => assinatura(l, 'teste', 7)}>
                      +7 dias teste
                    </button>
                    <button type="button" className="botao botao-secundario px-2 py-1 text-xs" onClick={() => assinatura(l, 'ativa', 30)}>
                      Ativar +30 dias
                    </button>
                    <button type="button" className="botao botao-secundario px-2 py-1 text-xs" onClick={() => assinatura(l, 'ativa', null)}>
                      Ativa sem prazo
                    </button>
                    {l.situacao_assinatura !== 'bloqueada' && (
                      <button
                        type="button"
                        className="botao botao-perigo px-2 py-1 text-xs"
                        onClick={() => window.confirm(`Bloquear ${l.nome_empresa}?`) && assinatura(l, 'bloqueada', null)}
                      >
                        Bloquear
                      </button>
                    )}
                  </div>
                </td>
                <td className="px-3 py-2.5 text-center">
                  <Interruptor
                    ligado={l.modulo_cardapio_ativo}
                    rotulo={`Cardápio de ${l.nome_empresa}`}
                    aoMudar={(v) => definir(l, v, l.modulo_whatsapp_ativo)}
                  />
                </td>
                <td className="px-3 py-2.5 text-center">
                  <div className="flex flex-col items-center gap-1">
                    <Interruptor
                      ligado={l.modulo_whatsapp_ativo}
                      rotulo={`WhatsApp de ${l.nome_empresa}`}
                      aoMudar={(v) => definir(l, l.modulo_cardapio_ativo, v)}
                    />
                    {l.modulo_whatsapp_ativo && (
                      <span className="text-xs text-zinc-500">
                        {l.status_conexao === 'connected' ? 'Conectado' : l.status_conexao ? 'Desconectado' : 'Não conectou ainda'}
                      </span>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function CelulaUso({ uso, aoVerPedidos }: { uso: UsoLoja | undefined; aoVerPedidos: () => void }) {
  if (!uso) return <span className="text-zinc-400">—</span>
  const ultimo = desdeUltimoPedido(uso.ultimo_pedido_em)
  return (
    <div className="min-w-[170px]">
      <p>
        <span className="text-base font-semibold tabular-nums">{uso.pedidos_7d}</span>{' '}
        <span className="text-zinc-500">{uso.pedidos_7d === 1 ? 'pedido' : 'pedidos'} em 7 dias</span>
      </p>
      <p className="text-xs text-zinc-500 tabular-nums">
        hoje {uso.pedidos_hoje} · 30 dias {uso.pedidos_30d} · {formatarMoeda(uso.faturamento_30d)}
      </p>
      {uso.pedidos_30d > 0 && (
        <p className="text-xs text-zinc-500 tabular-nums">
          cardápio {uso.pedidos_cardapio_30d} · WhatsApp {uso.pedidos_whatsapp_30d}
          {uso.cancelados_30d > 0 ? ` · ${uso.cancelados_30d} cancel.` : ''}
        </p>
      )}
      <p className={`mt-0.5 text-xs font-medium ${ultimo.cor}`}>{ultimo.texto}</p>
      {uso.ultimo_pedido_em && (
        <button type="button" className="mt-1 text-xs font-medium text-zinc-700 underline underline-offset-2 hover:text-zinc-900" onClick={aoVerPedidos}>
          Ver pedidos
        </button>
      )}
    </div>
  )
}
