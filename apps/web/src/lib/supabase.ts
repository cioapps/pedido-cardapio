import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const chave = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const supabaseConfigurado = Boolean(url && chave)

if (!supabaseConfigurado) {
  console.error('Defina VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY em apps/web/.env.local')
}

export const supabase = createClient(url || 'http://localhost:54321', chave || 'sem-chave')

/** Mensagem amigável a partir de um erro do Supabase/PostgREST */
export function mensagemErro(erro: unknown): string {
  if (!erro) return 'Erro desconhecido'
  if (typeof erro === 'object' && 'message' in erro) {
    const m = String((erro as { message: string }).message)
    if (m.includes('Invalid login credentials')) return 'E-mail ou senha incorretos'
    if (m.includes('User already registered')) return 'Este e-mail já está cadastrado'
    if (m.includes('Password should be')) return 'A senha deve ter pelo menos 6 caracteres'
    if (m.includes('Email not confirmed')) return 'Confirme seu e-mail antes de entrar'
    if (m.includes('Failed to fetch')) return 'Sem conexão. Verifique sua internet.'
    return m
  }
  return String(erro)
}
