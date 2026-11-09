import { useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { Contador, Folha } from '../componentes/Folha'
import { formatarMoeda, formatarTelefone, lerNumero, mascararTelefone } from '../lib/formatar'
import { mensagemErro, supabase } from '../lib/supabase'
import type { BairroCardapio, Cardapio } from '../lib/tipos'
import type { useCarrinho } from './carrinho'
import {
  bairroDaLoja,
  buscarPerfil,
  esquecerPerfil,
  registrarPedido,
  resumoEndereco,
  salvarPerfil,
  soDigitos,
  telefoneCompleto,
  ultimoTelefone,
  type EnderecoSalvo,
  type FormaPagamento,
  type PerfilCliente,
} from './clienteLocal'

interface Props {
  aberto: boolean
  aoFechar: () => void
  cardapio: Cardapio
  carrinho: ReturnType<typeof useCarrinho>
}

const OPCOES_PAGAMENTO: { valor: FormaPagamento; nome: string; icone: ReactNode }[] = [
  {
    valor: 'pix',
    nome: 'Pix',
    icone: (
      <>
        <path d="M12 2.8l9.2 9.2-9.2 9.2L2.8 12z" />
        <path d="M12 8.2l3.8 3.8-3.8 3.8-3.8-3.8z" />
      </>
    ),
  },
  {
    valor: 'cartao',
    nome: 'Cartão',
    icone: (
      <>
        <rect x="3" y="6" width="18" height="13" rx="2.5" />
        <path d="M3 10.5h18M7 15h3" />
      </>
    ),
  },
  {
    valor: 'dinheiro',
    nome: 'Dinheiro',
    icone: (
      <>
        <rect x="2.5" y="6.5" width="19" height="11" rx="2" />
        <circle cx="12" cy="12" r="2.5" />
      </>
    ),
  },
]

interface FormEndereco {
  logradouro: string
  numero_endereco: string
  complemento: string
  ponto_referencia: string
  id_bairro_entrega: number | null
}

const enderecoVazio: FormEndereco = {
  logradouro: '',
  numero_endereco: '',
  complemento: '',
  ponto_referencia: '',
  id_bairro_entrega: null,
}

/** 'novo' = digitando um endereço; senão, id de um endereço salvo */
type Escolha = 'novo' | string

/** Endereço salvo pronto para usar nesta loja? (o bairro precisa ser atendido) */
const situacaoEndereco = (e: EnderecoSalvo, bairros: BairroCardapio[]) => {
  if (!e.nome_bairro) return 'sem_bairro' as const
  return bairroDaLoja(e.nome_bairro, bairros) ? ('ok' as const) : ('fora_da_area' as const)
}

/** Endereço padrão primeiro, os demais na ordem em que foram usados */
const ordenarEnderecos = (perfil: PerfilCliente | null) =>
  perfil
    ? [...perfil.enderecos].sort(
        (a, b) => Number(b.id === perfil.id_endereco_padrao) - Number(a.id === perfil.id_endereco_padrao),
      )
    : []

function escolhaInicial(perfil: PerfilCliente | null, bairros: BairroCardapio[]): Escolha {
  if (!perfil) return 'novo'
  return ordenarEnderecos(perfil).find((e) => situacaoEndereco(e, bairros) === 'ok')?.id ?? 'novo'
}

export function Checkout({ aberto, aoFechar, cardapio, carrinho }: Props) {
  const [etapaEscolhida, setEtapa] = useState<'sacola' | 'finalizar'>('sacola')
  const { empresa } = cardapio
  const faltaMinimo = Math.max(0, Number(empresa.pedido_minimo) - carrinho.subtotal)
  const vazio = carrinho.itens.length === 0
  const etapa = vazio ? 'sacola' : etapaEscolhida

  const fechar = () => {
    setEtapa('sacola')
    aoFechar()
  }

  return (
    <Folha
      aberta={aberto}
      aoFechar={fechar}
      titulo={
        etapa === 'sacola' ? (
          'Sua sacola'
        ) : (
          <button
            type="button"
            className="-ml-1 flex items-center gap-1.5 rounded-lg pr-2 transition hover:text-zinc-600"
            onClick={() => setEtapa('sacola')}
            aria-label="Voltar para a sacola"
          >
            <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth={2.6}>
              <path d="M15 6l-6 6 6 6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Finalizar pedido
          </button>
        )
      }
      rodape={
        vazio ? undefined : etapa === 'sacola' ? (
          <button
            type="button"
            className="botao-loja w-full justify-between py-3.5"
            disabled={faltaMinimo > 0 || !empresa.loja_aberta}
            onClick={() => setEtapa('finalizar')}
          >
            <span>{!empresa.loja_aberta ? 'Loja fechada' : faltaMinimo > 0 ? 'Abaixo do mínimo' : 'Continuar'}</span>
            <span className="tabular-nums">{formatarMoeda(carrinho.subtotal)}</span>
          </button>
        ) : undefined
      }
    >
      {vazio ? (
        <div className="px-6 pb-14 pt-8 text-center">
          <p className="font-display text-xl font-extrabold">Sua sacola está vazia</p>
          <p className="mt-1 text-sm text-zinc-500">Toque em um produto do cardápio para adicionar.</p>
          <button type="button" className="botao botao-secundario mt-6" onClick={fechar}>
            Ver cardápio
          </button>
        </div>
      ) : etapa === 'sacola' ? (
        <Sacola cardapio={cardapio} carrinho={carrinho} faltaMinimo={faltaMinimo} aoContinuarComprando={fechar} />
      ) : (
        <Finalizar cardapio={cardapio} carrinho={carrinho} aoConcluir={fechar} />
      )}
    </Folha>
  )
}

function Sacola({
  cardapio: { empresa },
  carrinho,
  faltaMinimo,
  aoContinuarComprando,
}: {
  cardapio: Cardapio
  carrinho: Props['carrinho']
  faltaMinimo: number
  aoContinuarComprando: () => void
}) {
  const minimo = Number(empresa.pedido_minimo)
  return (
    <div className="pb-4">
      <ul className="divide-y divide-zinc-100 px-5">
        {carrinho.itens.map((item) => (
          <li key={item.chave} className="flex items-start gap-3 py-4">
            <div className="min-w-0 flex-1">
              <p className="font-semibold leading-snug">{item.nome_produto}</p>
              {item.opcoes.length > 0 && (
                <p className="mt-0.5 text-sm leading-snug text-zinc-500">
                  {item.opcoes
                    .map((o) => (o.quantidade > 1 ? `${o.quantidade}x ${o.nome_opcao}` : o.nome_opcao))
                    .join(', ')}
                </p>
              )}
              {item.observacao_item && (
                <p className="mt-0.5 text-sm italic text-zinc-500">“{item.observacao_item}”</p>
              )}
              <p className="mt-1.5 text-[15px] font-bold tabular-nums">
                {formatarMoeda(item.preco_unitario * item.quantidade)}
              </p>
            </div>
            <Contador pequeno valor={item.quantidade} aoMudar={(v) => carrinho.alterarQuantidade(item.chave, v)} />
          </li>
        ))}
      </ul>
      <div className="px-5">
        <button
          type="button"
          onClick={aoContinuarComprando}
          className="flex w-full items-center justify-center gap-2 rounded-xl border border-dashed border-zinc-300 py-3 text-sm font-semibold text-zinc-600 transition hover:border-zinc-400 hover:text-zinc-900"
        >
          <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth={2.6}>
            <path d="M12 5v14M5 12h14" strokeLinecap="round" />
          </svg>
          Adicionar mais itens
        </button>
        {faltaMinimo > 0 && (
          <div className="mt-4 rounded-xl bg-amber-50 p-3.5">
            <p className="text-sm text-amber-900">
              Faltam <strong>{formatarMoeda(faltaMinimo)}</strong> para o pedido mínimo de {formatarMoeda(minimo)}.
            </p>
            <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-amber-200/70">
              <div
                className="h-full rounded-full bg-amber-500 transition-[width] duration-500"
                style={{ width: `${Math.min(100, (carrinho.subtotal / minimo) * 100)}%` }}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function Secao({ titulo, children, acao }: { titulo: string; children: ReactNode; acao?: ReactNode }) {
  return (
    <section className="animate-[surgir_.25s_ease-out]">
      <div className="mb-2.5 flex items-baseline justify-between gap-2">
        <h3 className="font-display text-lg font-extrabold tracking-tight">{titulo}</h3>
        {acao}
      </div>
      {children}
    </section>
  )
}

function Finalizar({
  cardapio,
  carrinho,
  aoConcluir,
}: {
  cardapio: Cardapio
  carrinho: Props['carrinho']
  aoConcluir: () => void
}) {
  const navegar = useNavigate()
  const { empresa, bairros } = cardapio

  const [telefone, setTelefone] = useState(() => ultimoTelefone())
  const [perfil, setPerfil] = useState<PerfilCliente | null>(() => buscarPerfil(ultimoTelefone()))
  const [nome, setNome] = useState(() => perfil?.nome_cliente ?? '')
  const [editandoNome, setEditandoNome] = useState(false)
  const [escolha, setEscolha] = useState<Escolha>(() => escolhaInicial(perfil, bairros))
  const [form, setForm] = useState<FormEndereco>(enderecoVazio)
  const [idEditando, setIdEditando] = useState<string | null>(null)
  const [tornarPadrao, setTornarPadrao] = useState(false)
  const [pagamento, setPagamento] = useState<FormaPagamento | null>(() => perfil?.ultimo_pagamento ?? null)
  const [semTroco, setSemTroco] = useState(false)
  const [trocoPara, setTrocoPara] = useState('')
  const [mostrarObs, setMostrarObs] = useState(false)
  const [observacao, setObservacao] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const refTelefone = useRef<HTMLInputElement>(null)
  const refErro = useRef<HTMLParagraphElement>(null)

  useEffect(() => {
    if (erro) refErro.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }, [erro])

  const completo = telefoneCompleto(telefone)

  // Ao terminar de digitar o número, puxa o cadastro salvo neste celular
  const mudarTelefone = (valor: string) => {
    const digitos = valor.replace(/\D/g, '').slice(0, 11)
    setTelefone(digitos)
    setErro(null)
    const encontrado = buscarPerfil(digitos)
    if (encontrado?.telefone !== perfil?.telefone) {
      setPerfil(encontrado)
      setNome(encontrado?.nome_cliente ?? '')
      setEditandoNome(false)
      setEscolha(escolhaInicial(encontrado, bairros))
      setForm(enderecoVazio)
      setIdEditando(null)
      setTornarPadrao(false)
      if (encontrado?.ultimo_pagamento) setPagamento(encontrado.ultimo_pagamento)
    }
  }

  const trocarNumero = () => {
    setTelefone('')
    setPerfil(null)
    setNome('')
    setEscolha('novo')
    setForm(enderecoVazio)
    window.setTimeout(() => refTelefone.current?.focus(), 0)
  }

  const naoSouEu = () => {
    esquecerPerfil(telefone)
    trocarNumero()
  }

  const enderecoSalvo = perfil?.enderecos.find((e) => e.id === escolha) ?? null
  const bairro =
    escolha === 'novo'
      ? (bairros.find((b) => b.id === form.id_bairro_entrega) ?? null)
      : enderecoSalvo
        ? bairroDaLoja(enderecoSalvo.nome_bairro, bairros)
        : null
  const taxa = Number(bairro?.taxa_entrega ?? 0)
  const total = carrinho.subtotal + taxa

  /**
   * Leva um endereço salvo para o formulário (para corrigir ou escolher o bairro).
   * Bairro fora da lista desta loja: o original continua salvo como está (ele serve na
   * loja onde foi cadastrado) e o pedido aqui gera uma cópia com o bairro desta loja.
   */
  const editarEndereco = (e: EnderecoSalvo) => {
    const bairroAqui = bairroDaLoja(e.nome_bairro, bairros)
    setForm({
      logradouro: e.logradouro,
      numero_endereco: e.numero_endereco,
      complemento: e.complemento,
      ponto_referencia: e.ponto_referencia,
      id_bairro_entrega: bairroAqui?.id ?? null,
    })
    setIdEditando(e.nome_bairro && !bairroAqui ? null : e.id)
    setEscolha('novo')
  }

  const novoEndereco = () => {
    setForm(enderecoVazio)
    setIdEditando(null)
    setEscolha('novo')
  }

  const atualizarForm = <K extends keyof FormEndereco>(campo: K, valor: FormEndereco[K]) =>
    setForm((f) => ({ ...f, [campo]: valor }))

  const enviar = async (e: FormEvent) => {
    e.preventDefault()
    setErro(null)
    if (!completo) return setErro('Informe seu WhatsApp com DDD')
    if (!nome.trim()) return setErro('Informe seu nome')
    if (!bairro) return setErro('Escolha o bairro de entrega')
    if (escolha === 'novo' && (!form.logradouro.trim() || !form.numero_endereco.trim()))
      return setErro('Informe a rua e o número para a entrega')
    if (!pagamento) return setErro('Escolha como vai pagar')
    const troco = pagamento === 'dinheiro' && !semTroco && trocoPara.trim() ? lerNumero(trocoPara) : null
    if (pagamento === 'dinheiro' && !semTroco && !trocoPara.trim())
      return setErro('Diga para quanto precisa de troco, ou marque "Não preciso de troco"')
    if (troco !== null && troco < total) return setErro(`O troco precisa ser para um valor acima de ${formatarMoeda(total)}`)

    const endereco =
      escolha === 'novo'
        ? {
            logradouro: form.logradouro.trim(),
            numero_endereco: form.numero_endereco.trim(),
            complemento: form.complemento.trim(),
            ponto_referencia: form.ponto_referencia.trim(),
            nome_bairro: bairro.nome_bairro,
          }
        : {
            logradouro: enderecoSalvo!.logradouro,
            numero_endereco: enderecoSalvo!.numero_endereco,
            complemento: enderecoSalvo!.complemento,
            ponto_referencia: enderecoSalvo!.ponto_referencia,
            nome_bairro: bairro.nome_bairro,
          }

    setEnviando(true)
    const { data, error } = await supabase.rpc('criar_pedido', {
      p_dados: {
        slug_empresa: empresa.slug_empresa,
        nome_cliente: nome.trim(),
        telefone_cliente: soDigitos(telefone),
        logradouro: endereco.logradouro,
        numero_endereco: endereco.numero_endereco,
        complemento: endereco.complemento,
        ponto_referencia: endereco.ponto_referencia,
        id_bairro_entrega: bairro.id,
        forma_pagamento: pagamento,
        troco_para: troco,
        observacao_pedido: observacao,
        itens: carrinho.itens.map((i) => ({
          id_produto: i.id_produto,
          quantidade: i.quantidade,
          observacao_item: i.observacao_item,
          opcoes: i.opcoes.map((o) => ({ id_opcao: o.id_opcao, quantidade: o.quantidade })),
        })),
      },
    })
    setEnviando(false)
    if (error) return setErro(mensagemErro(error))

    salvarPerfil(
      telefone,
      nome,
      endereco,
      tornarPadrao || !perfil?.enderecos.length,
      pagamento,
      escolha === 'novo' ? idEditando : null,
    )
    registrarPedido({
      codigo: data.codigo_acompanhamento,
      slug: empresa.slug_empresa,
      nome_empresa: empresa.nome_empresa,
      cor_principal: empresa.cor_principal,
      numero_pedido: data.numero_pedido,
      valor_total: Number(data.valor_total),
      criado_em: new Date().toISOString(),
    })
    carrinho.limpar()
    aoConcluir()
    navegar(`/${empresa.slug_empresa}/pedido/${data.codigo_acompanhamento}?novo=1`)
  }

  const enderecosOrdenados = useMemo(() => ordenarEnderecos(perfil), [perfil])

  return (
    <form onSubmit={enviar} className="space-y-7 px-5 pb-5 pt-2" noValidate>
      <Secao titulo="Seu WhatsApp">
        <div className="relative">
          <input
            ref={refTelefone}
            id="telefone"
            className="campo pr-11 text-lg font-semibold tracking-wide tabular-nums"
            inputMode="tel"
            autoComplete="tel-national"
            placeholder="(00) 00000-0000"
            aria-label="Seu WhatsApp com DDD"
            value={mascararTelefone(telefone)}
            onChange={(e) => mudarTelefone(e.target.value)}
            autoFocus={!telefone}
          />
          {completo && (
            <span className="absolute right-3.5 top-1/2 grid size-6 -translate-y-1/2 place-items-center rounded-full bg-emerald-500 text-white">
              <svg viewBox="0 0 24 24" className="size-3.5" fill="none" stroke="currentColor" strokeWidth={3.5}>
                <path d="M5 12.5l4.5 4.5L19 7.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          )}
        </div>
        {!completo && (
          <p className="mt-2 text-sm text-zinc-500">
            A loja usa este número para falar com você sobre o pedido.
          </p>
        )}

        {completo && perfil && !editandoNome && (
          <div className="mt-3 flex items-center gap-3 rounded-2xl bg-loja-suave p-3.5 animate-[surgir_.25s_ease-out]">
            <span className="grid size-10 shrink-0 place-items-center rounded-full bg-loja font-display text-lg font-extrabold text-[var(--sobre-loja)]">
              {perfil.nome_cliente.charAt(0).toUpperCase()}
            </span>
            <div className="min-w-0 flex-1">
              <p className="font-semibold">Que bom te ver, {nome.split(' ')[0]}!</p>
              <p className="text-sm text-zinc-600">Seus dados já estão preenchidos.</p>
            </div>
            <button
              type="button"
              className="shrink-0 text-sm font-semibold text-loja-escura underline-offset-2 hover:underline"
              onClick={() => setEditandoNome(true)}
            >
              Alterar nome
            </button>
          </div>
        )}

        {completo && (!perfil || editandoNome) && (
          <div className="mt-3 animate-[surgir_.25s_ease-out]">
            <label className="rotulo" htmlFor="nome">
              Seu nome
            </label>
            <input
              id="nome"
              className="campo"
              maxLength={120}
              autoComplete="name"
              placeholder="Como a loja deve te chamar"
              value={nome}
              onChange={(e) => setNome(e.target.value)}
              autoFocus={!perfil}
            />
          </div>
        )}

        {completo && perfil && (
          <p className="mt-2 text-xs text-zinc-500">
            Não é você?{' '}
            <button type="button" className="font-semibold underline underline-offset-2" onClick={naoSouEu}>
              Apagar os dados de {formatarTelefone(telefone)} deste celular
            </button>
          </p>
        )}
      </Secao>

      {completo && (
        <>
          <Secao
            titulo="Entregar em"
            acao={
              escolha === 'novo' && enderecosOrdenados.length > 0 ? (
                <button
                  type="button"
                  className="text-sm font-semibold text-loja-escura"
                  onClick={() => setEscolha(escolhaInicial(perfil, bairros))}
                >
                  Usar salvo
                </button>
              ) : undefined
            }
          >
            {escolha !== 'novo' && (
              <div className="space-y-2" role="radiogroup" aria-label="Endereço de entrega">
                {enderecosOrdenados.map((e) => {
                  const situacao = situacaoEndereco(e, bairros)
                  const marcado = escolha === e.id
                  const taxaBairro = bairroDaLoja(e.nome_bairro, bairros)?.taxa_entrega
                  return (
                    <div
                      key={e.id}
                      className={`rounded-2xl border-2 p-3.5 transition ${
                        marcado ? 'border-loja bg-loja-suave' : 'border-zinc-200'
                      } ${situacao === 'fora_da_area' ? 'border-dashed' : ''}`}
                    >
                      <button
                        type="button"
                        role="radio"
                        aria-checked={marcado}
                        onClick={() => (situacao === 'ok' ? setEscolha(e.id) : editarEndereco(e))}
                        className="flex w-full items-start gap-3 text-left"
                      >
                        <span
                          className={`mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border-2 ${
                            marcado ? 'border-loja' : 'border-zinc-300'
                          }`}
                        >
                          {marcado && <span className="size-2.5 rounded-full bg-loja" />}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
                            <span className="font-semibold">{resumoEndereco(e)}</span>
                            {e.id === perfil?.id_endereco_padrao && (
                              <span className="rounded-full bg-zinc-900 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
                                Padrão
                              </span>
                            )}
                          </span>
                          <span className="mt-0.5 block text-sm text-zinc-500">
                            {situacao === 'ok' &&
                              `${e.nome_bairro} · entrega ${Number(taxaBairro) > 0 ? formatarMoeda(taxaBairro) : 'grátis'}`}
                            {situacao === 'sem_bairro' && 'Toque para escolher o bairro'}
                            {situacao === 'fora_da_area' &&
                              `${e.nome_bairro} não está na lista desta loja · toque para escolher o bairro`}
                          </span>
                        </span>
                      </button>
                      {marcado && (
                        <button
                          type="button"
                          className="ml-8 mt-2 text-sm font-semibold text-loja-escura underline-offset-2 hover:underline"
                          onClick={() => editarEndereco(e)}
                        >
                          Corrigir este endereço
                        </button>
                      )}
                    </div>
                  )
                })}
                <button
                  type="button"
                  onClick={novoEndereco}
                  className="flex w-full items-center gap-3 rounded-2xl border-2 border-dashed border-zinc-300 p-3.5 text-left font-semibold text-zinc-700 transition hover:border-zinc-400"
                >
                  <span className="grid size-5 place-items-center text-loja">
                    <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth={2.6}>
                      <path d="M12 5v14M5 12h14" strokeLinecap="round" />
                    </svg>
                  </span>
                  Entregar em outro endereço
                </button>
              </div>
            )}

            {escolha === 'novo' && (
              <div className="space-y-3">
                <div>
                  <label className="rotulo" htmlFor="bairro">
                    Bairro
                  </label>
                  <select
                    id="bairro"
                    className="campo"
                    value={form.id_bairro_entrega ?? ''}
                    onChange={(e) => atualizarForm('id_bairro_entrega', e.target.value ? Number(e.target.value) : null)}
                  >
                    <option value="">Escolha o bairro</option>
                    {bairros.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.nome_bairro} · {Number(b.taxa_entrega) > 0 ? formatarMoeda(b.taxa_entrega) : 'entrega grátis'}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="flex gap-3">
                  <div className="min-w-0 flex-1">
                    <label className="rotulo" htmlFor="rua">
                      Rua
                    </label>
                    <input
                      id="rua"
                      className="campo"
                      required
                      maxLength={200}
                      autoComplete="address-line1"
                      value={form.logradouro}
                      onChange={(e) => atualizarForm('logradouro', e.target.value)}
                    />
                  </div>
                  <div className="w-24">
                    <label className="rotulo" htmlFor="numero">
                      Número
                    </label>
                    <input
                      id="numero"
                      className="campo"
                      required
                      maxLength={20}
                      inputMode="numeric"
                      value={form.numero_endereco}
                      onChange={(e) => atualizarForm('numero_endereco', e.target.value)}
                    />
                  </div>
                </div>
                <div>
                  <label className="rotulo" htmlFor="complemento">
                    Complemento <span className="font-normal text-zinc-400">(opcional)</span>
                  </label>
                  <input
                    id="complemento"
                    className="campo"
                    maxLength={120}
                    placeholder="Apto, bloco, casa dos fundos"
                    value={form.complemento}
                    onChange={(e) => atualizarForm('complemento', e.target.value)}
                  />
                </div>
                <div>
                  <label className="rotulo" htmlFor="referencia">
                    Ponto de referência <span className="font-normal text-zinc-400">(opcional)</span>
                  </label>
                  <input
                    id="referencia"
                    className="campo"
                    maxLength={200}
                    placeholder="Ex.: perto da padaria"
                    value={form.ponto_referencia}
                    onChange={(e) => atualizarForm('ponto_referencia', e.target.value)}
                  />
                </div>
                {enderecosOrdenados.length > 0 && (
                  <label className="flex cursor-pointer items-center gap-2.5 py-1 text-[15px]">
                    <input
                      type="checkbox"
                      className="size-5 accent-loja"
                      checked={tornarPadrao}
                      onChange={(e) => setTornarPadrao(e.target.checked)}
                    />
                    Usar como meu endereço padrão
                  </label>
                )}
              </div>
            )}
          </Secao>

          <Secao titulo="Pagamento na entrega">
            <div className="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Forma de pagamento">
              {OPCOES_PAGAMENTO.map((p) => {
                const marcado = pagamento === p.valor
                return (
                  <button
                    key={p.valor}
                    type="button"
                    role="radio"
                    aria-checked={marcado}
                    onClick={() => setPagamento(p.valor)}
                    className={`flex flex-col items-center gap-1.5 rounded-2xl border-2 py-3 text-sm font-semibold transition active:scale-[0.97] ${
                      marcado ? 'border-loja bg-loja-suave text-zinc-900' : 'border-zinc-200 text-zinc-600 hover:border-zinc-300'
                    }`}
                  >
                    <svg
                      viewBox="0 0 24 24"
                      className={`size-6 ${marcado ? 'text-loja' : 'text-zinc-400'}`}
                      fill="none"
                      stroke="currentColor"
                      strokeWidth={1.8}
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      {p.icone}
                    </svg>
                    {p.nome}
                  </button>
                )
              })}
            </div>
            {pagamento === 'cartao' && (
              <p className="mt-2 text-sm text-zinc-500">Débito ou crédito na maquininha do entregador.</p>
            )}
            {pagamento === 'pix' && <p className="mt-2 text-sm text-zinc-500">Você paga o Pix na hora da entrega.</p>}
            {pagamento === 'dinheiro' && (
              <div className="mt-3 space-y-2 animate-[surgir_.2s_ease-out]">
                {!semTroco && (
                  <div className="relative">
                    <span className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-zinc-500">
                      Troco para R$
                    </span>
                    <input
                      className="campo pl-[7.5rem] font-semibold tabular-nums"
                      inputMode="decimal"
                      placeholder="100"
                      aria-label="Troco para quanto"
                      value={trocoPara}
                      onChange={(e) => setTrocoPara(e.target.value)}
                    />
                  </div>
                )}
                <label className="flex cursor-pointer items-center gap-2.5 text-[15px]">
                  <input
                    type="checkbox"
                    className="size-5 accent-loja"
                    checked={semTroco}
                    onChange={(e) => setSemTroco(e.target.checked)}
                  />
                  Não preciso de troco
                </label>
              </div>
            )}
          </Secao>

          <div>
            {mostrarObs ? (
              <div className="animate-[surgir_.2s_ease-out]">
                <label className="rotulo" htmlFor="obs-pedido">
                  Observação para a loja
                </label>
                <textarea
                  id="obs-pedido"
                  className="campo resize-none"
                  rows={2}
                  maxLength={500}
                  placeholder="Ex.: interfone quebrado, ligar ao chegar"
                  value={observacao}
                  onChange={(e) => setObservacao(e.target.value)}
                  autoFocus
                />
              </div>
            ) : (
              <button
                type="button"
                className="text-sm font-semibold text-zinc-600 underline underline-offset-2"
                onClick={() => setMostrarObs(true)}
              >
                Adicionar observação ao pedido
              </button>
            )}
          </div>

          <dl className="space-y-1.5 border-t border-dashed border-zinc-300 pt-4 text-[15px]">
            <div className="flex justify-between text-zinc-600">
              <dt>Produtos</dt>
              <dd className="tabular-nums">{formatarMoeda(carrinho.subtotal)}</dd>
            </div>
            <div className="flex justify-between text-zinc-600">
              <dt>Entrega</dt>
              <dd className="tabular-nums">{bairro ? (taxa > 0 ? formatarMoeda(taxa) : 'Grátis') : 'escolha o bairro'}</dd>
            </div>
            <div className="flex justify-between pt-1 text-lg font-bold">
              <dt>Total</dt>
              <dd className="tabular-nums">{formatarMoeda(total)}</dd>
            </div>
          </dl>
        </>
      )}

      {erro && (
        <p ref={refErro} role="alert" className="rounded-xl bg-red-50 px-3.5 py-2.5 text-sm font-medium text-red-700">
          {erro}
        </p>
      )}

      <div className="sticky bottom-0 -mx-5 border-t border-zinc-100 bg-white px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3">
        <button type="submit" className="botao-loja w-full justify-between py-3.5" disabled={enviando || !completo}>
          <span>{enviando ? 'Enviando pedido...' : completo ? 'Fazer pedido' : 'Informe seu WhatsApp'}</span>
          <span className="tabular-nums">{formatarMoeda(total)}</span>
        </button>
        <p className="mt-2 text-center text-xs text-zinc-400">
          Seus dados ficam salvos só neste celular, para agilizar os próximos pedidos.
        </p>
      </div>
    </form>
  )
}
