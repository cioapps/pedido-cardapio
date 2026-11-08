import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { StatusPedido } from '../lib/tipos'
import { listarPedidos, type PedidoSalvo } from './clienteLocal'

const UM_DIA = 24 * 60 * 60 * 1000
export const FINALIZADOS: StatusPedido[] = ['entregue', 'cancelado']

export interface PedidoComStatus extends PedidoSalvo {
  status?: StatusPedido
}

export const pedidoEmAndamento = (p: PedidoComStatus) =>
  !!p.status && !FINALIZADOS.includes(p.status)

/**
 * Pedidos feitos neste aparelho. Busca o status só dos das últimas 24h
 * (no máximo 5), atualizando a cada 30s enquanto algum estiver em andamento.
 */
export function usePedidosSalvos() {
  const [pedidos, setPedidos] = useState<PedidoComStatus[]>(() => listarPedidos())

  useEffect(() => {
    let cancelado = false
    let intervalo = 0
    const atualizar = async () => {
      const lista = listarPedidos()
      const recentes = lista.filter((p) => Date.now() - new Date(p.criado_em).getTime() < UM_DIA).slice(0, 5)
      const status = await Promise.all(
        recentes.map(async (p) => {
          const { data } = await supabase.rpc('consultar_pedido', { p_codigo: p.codigo })
          return [p.codigo, (data as { status_pedido?: StatusPedido } | null)?.status_pedido] as const
        }),
      )
      if (cancelado) return
      const mapa = new Map(status)
      const novos = lista.map((p) => ({ ...p, status: mapa.get(p.codigo) }))
      setPedidos(novos)
      if (!novos.some(pedidoEmAndamento)) window.clearInterval(intervalo)
    }
    atualizar()
    intervalo = window.setInterval(atualizar, 30_000)
    return () => {
      cancelado = true
      window.clearInterval(intervalo)
    }
  }, [])

  return pedidos
}
