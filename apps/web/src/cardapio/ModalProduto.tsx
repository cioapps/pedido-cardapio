import { useMemo, useState } from 'react'
import { Contador, Folha } from '../componentes/Folha'
import { formatarMoeda } from '../lib/formatar'
import type { GrupoCardapio, ItemCarrinho, OpcaoEscolhida, ProdutoCardapio } from '../lib/tipos'

interface Props {
  produto: ProdutoCardapio | null
  lojaAberta: boolean
  aoFechar: () => void
  aoAdicionar: (item: Omit<ItemCarrinho, 'chave'>) => void
}

/** quantidade escolhida por opção, agrupada por grupo */
type Selecoes = Record<number, Record<number, number>>

const somaGrupo = (s: Selecoes, idGrupo: number) =>
  Object.values(s[idGrupo] ?? {}).reduce((a, b) => a + b, 0)

const descricaoRegra = (g: GrupoCardapio) => {
  if (g.minimo_selecao === 1 && g.maximo_selecao === 1) return 'Escolha 1'
  if (g.minimo_selecao > 0 && g.minimo_selecao === g.maximo_selecao)
    return `Escolha ${g.minimo_selecao}`
  if (g.minimo_selecao > 0) return `Escolha de ${g.minimo_selecao} a ${g.maximo_selecao}`
  return `Opcional · até ${g.maximo_selecao}`
}

export function ModalProduto({ produto, lojaAberta, aoFechar, aoAdicionar }: Props) {
  return (
    <Folha
      aberta={!!produto}
      aoFechar={aoFechar}
      titulo={produto?.nome_produto}
      semCabecalho={!!produto?.foto_url}
    >
      {produto && (
        <ConteudoProduto
          key={produto.id}
          produto={produto}
          lojaAberta={lojaAberta}
          aoFechar={aoFechar}
          aoAdicionar={aoAdicionar}
        />
      )}
    </Folha>
  )
}

function Marcador({ marcado, redondo }: { marcado: boolean; redondo: boolean }) {
  return (
    <span
      className={`grid size-6 shrink-0 place-items-center border-2 transition ${redondo ? 'rounded-full' : 'rounded-md'} ${
        marcado ? 'border-loja bg-loja text-[var(--sobre-loja)]' : 'border-zinc-300 bg-white'
      }`}
      aria-hidden
    >
      {marcado &&
        (redondo ? (
          <span className="size-2 rounded-full bg-current" />
        ) : (
          <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="currentColor" strokeWidth={3.5}>
            <path d="M5 12.5l4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        ))}
    </span>
  )
}

function ConteudoProduto({
  produto,
  lojaAberta,
  aoFechar,
  aoAdicionar,
}: Props & { produto: ProdutoCardapio }) {
  const [selecoes, setSelecoes] = useState<Selecoes>({})
  const [quantidade, setQuantidade] = useState(1)
  const [observacao, setObservacao] = useState('')
  const [tentouEnviar, setTentouEnviar] = useState(false)

  const pendentes = produto.grupos.filter((g) => somaGrupo(selecoes, g.id) < g.minimo_selecao)

  const precoUnitario = useMemo(() => {
    let total = Number(produto.preco_produto)
    for (const g of produto.grupos) {
      for (const o of g.opcoes) {
        total += Number(o.preco_adicional) * (selecoes[g.id]?.[o.id] ?? 0)
      }
    }
    return total
  }, [produto, selecoes])

  const escolherUnica = (g: GrupoCardapio, idOpcao: number) =>
    setSelecoes((s) => ({ ...s, [g.id]: { [idOpcao]: 1 } }))

  const alternarMarcada = (g: GrupoCardapio, idOpcao: number) =>
    setSelecoes((s) => {
      const atual = { ...(s[g.id] ?? {}) }
      if (atual[idOpcao]) delete atual[idOpcao]
      else if (somaGrupo(s, g.id) < g.maximo_selecao) atual[idOpcao] = 1
      return { ...s, [g.id]: atual }
    })

  const mudarQuantidadeOpcao = (g: GrupoCardapio, idOpcao: number, qtd: number) =>
    setSelecoes((s) => {
      const atual = { ...(s[g.id] ?? {}) }
      const outros = somaGrupo(s, g.id) - (atual[idOpcao] ?? 0)
      const permitido = Math.max(0, Math.min(qtd, g.maximo_selecao - outros))
      if (permitido === 0) delete atual[idOpcao]
      else atual[idOpcao] = permitido
      return { ...s, [g.id]: atual }
    })

  const adicionar = () => {
    setTentouEnviar(true)
    if (pendentes.length > 0) {
      document.getElementById(`grupo-${pendentes[0].id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
      return
    }
    const opcoes: OpcaoEscolhida[] = []
    for (const g of produto.grupos) {
      for (const o of g.opcoes) {
        const qtd = selecoes[g.id]?.[o.id] ?? 0
        if (qtd > 0) {
          opcoes.push({
            id_opcao: o.id,
            nome_opcao: o.nome_opcao,
            nome_grupo: g.nome_grupo,
            preco_adicional: Number(o.preco_adicional),
            quantidade: qtd,
          })
        }
      }
    }
    aoAdicionar({
      id_produto: produto.id,
      nome_produto: produto.nome_produto,
      preco_unitario: precoUnitario,
      quantidade,
      observacao_item: observacao.trim(),
      opcoes,
    })
    aoFechar()
  }

  return (
    <>
      <div>
        {produto.foto_url && (
          <>
            <img src={produto.foto_url} alt="" className="aspect-[4/3] w-full bg-zinc-100 object-cover" />
            <h2 className="px-5 pt-4 font-display text-2xl font-extrabold leading-tight tracking-tight">
              {produto.nome_produto}
            </h2>
          </>
        )}
        <div className="px-5 pb-4 pt-1">
          {produto.descricao_produto && (
            <p className="text-[15px] leading-relaxed text-zinc-600">{produto.descricao_produto}</p>
          )}
          <p className="mt-2 text-lg font-bold tabular-nums">{formatarMoeda(produto.preco_produto)}</p>
        </div>

        {produto.grupos.map((g) => {
          const unica = g.maximo_selecao === 1
          const soma = somaGrupo(selecoes, g.id)
          const completo = soma >= g.minimo_selecao
          const faltando = tentouEnviar && !completo
          return (
            <section key={g.id} id={`grupo-${g.id}`} className="scroll-mt-2">
              <div
                className={`sticky top-0 z-10 flex items-center justify-between gap-2 px-5 py-3 transition-colors ${
                  faltando ? 'bg-red-50' : 'bg-zinc-100/95 backdrop-blur'
                }`}
              >
                <div>
                  <h3 className="font-bold">{g.nome_grupo}</h3>
                  <p className={`text-xs ${faltando ? 'font-semibold text-red-600' : 'text-zinc-500'}`}>
                    {descricaoRegra(g)}
                    {g.maximo_selecao > 1 && soma > 0 && ` · ${soma} de ${g.maximo_selecao}`}
                  </p>
                </div>
                {g.minimo_selecao > 0 && (
                  <span
                    className={`rounded-full px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide ${
                      completo ? 'bg-emerald-100 text-emerald-700' : faltando ? 'bg-red-600 text-white' : 'bg-zinc-900 text-white'
                    }`}
                  >
                    {completo ? '✓ Pronto' : 'Obrigatório'}
                  </span>
                )}
              </div>
              <ul className="divide-y divide-zinc-100">
                {g.opcoes.map((o) => {
                  const qtd = selecoes[g.id]?.[o.id] ?? 0
                  const preco = Number(o.preco_adicional) > 0 ? `+ ${formatarMoeda(o.preco_adicional)}` : null
                  if (unica || g.maximo_selecao <= 3) {
                    const cheio = !unica && !qtd && soma >= g.maximo_selecao
                    return (
                      <li key={o.id}>
                        <label
                          className={`flex cursor-pointer items-center gap-3 px-5 py-3.5 transition hover:bg-zinc-50 ${
                            cheio ? 'opacity-40' : ''
                          }`}
                        >
                          <input
                            type={unica ? 'radio' : 'checkbox'}
                            name={`grupo-${g.id}`}
                            className="peer sr-only"
                            checked={qtd > 0}
                            disabled={cheio}
                            onChange={() => (unica ? escolherUnica(g, o.id) : alternarMarcada(g, o.id))}
                          />
                          <span className="flex-1">
                            <span className={`block text-[15px] ${qtd ? 'font-semibold' : ''}`}>{o.nome_opcao}</span>
                            {preco && <span className="text-sm text-zinc-500">{preco}</span>}
                          </span>
                          <span className="rounded-md peer-focus-visible:ring-2 peer-focus-visible:ring-loja">
                            <Marcador marcado={qtd > 0} redondo={unica} />
                          </span>
                        </label>
                      </li>
                    )
                  }
                  return (
                    <li key={o.id} className="flex items-center gap-3 px-5 py-2.5">
                      <span className="flex-1">
                        <span className={`block text-[15px] ${qtd ? 'font-semibold' : ''}`}>{o.nome_opcao}</span>
                        {preco && <span className="text-sm text-zinc-500">{preco}</span>}
                      </span>
                      <Contador
                        pequeno
                        valor={qtd}
                        maximo={qtd + (g.maximo_selecao - soma)}
                        aoMudar={(v) => mudarQuantidadeOpcao(g, o.id, v)}
                      />
                    </li>
                  )
                })}
              </ul>
            </section>
          )
        })}

        <div className="px-5 pb-5 pt-4">
          <label className="rotulo" htmlFor="obs-item">
            Alguma observação?
          </label>
          <textarea
            id="obs-item"
            className="campo resize-none"
            rows={2}
            maxLength={300}
            placeholder="Ex.: sem cebola, maionese à parte"
            value={observacao}
            onChange={(e) => setObservacao(e.target.value)}
          />
        </div>
      </div>

      <div className="sticky bottom-0 z-20 flex items-center gap-3 border-t border-zinc-100 bg-white p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
        <Contador valor={quantidade} minimo={1} aoMudar={setQuantidade} />
        <button
          type="button"
          className="botao-loja flex-1 justify-between"
          onClick={adicionar}
          disabled={!lojaAberta}
        >
          <span>{!lojaAberta ? 'Loja fechada' : pendentes.length > 0 && tentouEnviar ? 'Faltam escolhas' : 'Adicionar'}</span>
          <span className="tabular-nums">{formatarMoeda(precoUnitario * quantidade)}</span>
        </button>
      </div>
    </>
  )
}
