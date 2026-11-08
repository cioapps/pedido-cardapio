import type { CSSProperties } from 'react'

/** Texto branco ou escuro, conforme a cor da loja for escura ou clara */
export function corTextoSobre(hex: string | null | undefined) {
  const m = (hex ?? '').replace('#', '').match(/^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i)
  if (!m) return '#ffffff'
  const [r, g, b] = m.slice(1).map((c) => {
    const v = parseInt(c, 16) / 255
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.45 ? '#16181d' : '#ffffff'
}

export const estiloLoja = (cor: string | null | undefined) =>
  ({ '--cor-loja': cor, '--sobre-loja': corTextoSobre(cor) }) as CSSProperties
