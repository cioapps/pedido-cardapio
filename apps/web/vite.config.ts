import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig, loadEnv } from 'vite'

export default defineConfig(({ command, mode }) => {
  // Sem estas variáveis o site publicado tenta falar com localhost e a loja
  // aparece como "sem internet". Barra o build em vez de publicar quebrado.
  if (command === 'build') {
    const env = loadEnv(mode, process.cwd())
    const faltando = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'].filter((n) => !env[n])
    if (faltando.length) {
      throw new Error(`Build cancelado: falta ${faltando.join(', ')} em apps/web/.env.local`)
    }
  }
  return { plugins: [react(), tailwindcss()] }
})
