const HORA = 3_600_000

/** "Último pedido há 2 h" com cor: verde até 1 dia, âmbar até 7 dias, vermelho depois disso ou se nunca pediu */
export function desdeUltimoPedido(iso: string | null) {
  if (!iso) return { texto: 'Nenhum pedido ainda', cor: 'text-red-700' }
  const horas = (Date.now() - new Date(iso).getTime()) / HORA
  const texto = `Último pedido ${tempoRelativo(iso)}`
  if (horas < 24) return { texto, cor: 'text-emerald-700' }
  if (horas < 24 * 7) return { texto, cor: 'text-amber-700' }
  return { texto, cor: 'text-red-700' }
}

export function tempoRelativo(iso: string) {
  const min = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60_000))
  if (min < 1) return 'agora'
  if (min < 60) return `há ${min} min`
  const h = Math.round(min / 60)
  if (h < 24) return `há ${h} h`
  const d = Math.round(h / 24)
  return `há ${d} ${d === 1 ? 'dia' : 'dias'}`
}

