import { useCallback, useEffect, useState } from 'react'
import type { ItemCarrinho } from '../lib/tipos'

const chaveStorage = (slug: string) => `carrinho:${slug}`

function lerStorage<T>(chave: string, padrao: T): T {
  try {
    const bruto = localStorage.getItem(chave)
    return bruto ? (JSON.parse(bruto) as T) : padrao
  } catch {
    return padrao
  }
}

function gravarStorage(chave: string, valor: unknown) {
  try {
    localStorage.setItem(chave, JSON.stringify(valor))
  } catch {
    /* modo anônimo / storage cheio: segue só em memória */
  }
}

/** Identifica itens iguais (mesmo produto, opções e observação) para somar quantidade */
export const gerarChaveItem = (item: Omit<ItemCarrinho, 'chave' | 'quantidade'>) =>
  [
    item.id_produto,
    item.opcoes
      .map((o) => `${o.id_opcao}x${o.quantidade}`)
      .sort()
      .join(','),
    item.observacao_item.trim().toLowerCase(),
  ].join('|')

export function useCarrinho(slug: string) {
  // A página do cardápio é remontada por slug (key={slug}), então ler só no início basta
  const [itens, setItens] = useState<ItemCarrinho[]>(() => lerStorage(chaveStorage(slug), []))

  useEffect(() => {
    gravarStorage(chaveStorage(slug), itens)
  }, [slug, itens])

  const adicionar = useCallback((novo: Omit<ItemCarrinho, 'chave'>) => {
    const chave = gerarChaveItem(novo)
    setItens((atual) => {
      const existente = atual.find((i) => i.chave === chave)
      if (existente) {
        return atual.map((i) =>
          i.chave === chave ? { ...i, quantidade: Math.min(99, i.quantidade + novo.quantidade) } : i,
        )
      }
      return [...atual, { ...novo, chave }]
    })
  }, [])

  const alterarQuantidade = useCallback((chave: string, quantidade: number) => {
    setItens((atual) =>
      quantidade <= 0
        ? atual.filter((i) => i.chave !== chave)
        : atual.map((i) => (i.chave === chave ? { ...i, quantidade: Math.min(99, quantidade) } : i)),
    )
  }, [])

  const limpar = useCallback(() => setItens([]), [])

  const subtotal = itens.reduce((s, i) => s + i.preco_unitario * i.quantidade, 0)
  const quantidadeTotal = itens.reduce((s, i) => s + i.quantidade, 0)

  return { itens, adicionar, alterarQuantidade, limpar, subtotal, quantidadeTotal }
}
