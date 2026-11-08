/**
 * Cloudflare Pages Function para /:slug
 * Injeta título, descrição e logo da loja nas meta tags (Open Graph),
 * para o link do cardápio mostrar preview bonito no WhatsApp.
 * O restante continua sendo a SPA normal.
 */

interface Env {
  SUPABASE_URL: string
  SUPABASE_ANON_KEY: string
}

interface Contexto {
  request: Request
  env: Env
  params: { slug: string }
  next: () => Promise<Response>
}

// HTMLRewriter existe no runtime da Cloudflare
declare const HTMLRewriter: {
  new (): {
    on(seletor: string, handler: { element(el: { setAttribute(n: string, v: string): void; setInnerContent(t: string): void }): void }): any
    transform(r: Response): Response
  }
}

const ROTAS_RESERVADAS = new Set(['painel', 'admin', 'assets', 'favicon.svg', 'robots.txt'])

const escapar = (t: string) => t.replace(/[<>&"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' })[c]!)

export const onRequestGet = async ({ request, env, params, next }: Contexto) => {
  const resposta = await next()
  const slug = String(params.slug || '')
  const tipo = resposta.headers.get('content-type') || ''

  if (ROTAS_RESERVADAS.has(slug) || !tipo.includes('text/html') || !env.SUPABASE_URL) return resposta

  try {
    const url = `${env.SUPABASE_URL}/rest/v1/empresas?slug_empresa=eq.${encodeURIComponent(slug)}&ativo=eq.true&select=nome_empresa,logo_url,cor_principal,tempo_entrega_minutos`
    const r = await fetch(url, {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
      cf: { cacheTtl: 300, cacheEverything: true },
    } as RequestInit)
    const [empresa] = (await r.json()) as {
      nome_empresa: string
      logo_url: string | null
      cor_principal: string
      tempo_entrega_minutos: number
    }[]
    if (!empresa) return resposta

    const titulo = escapar(`${empresa.nome_empresa} · Cardápio`)
    const descricao = escapar(`Veja o cardápio e faça seu pedido online. Entrega em ~${empresa.tempo_entrega_minutos} min.`)
    const pagina = new URL(request.url).origin + '/' + slug

    const conteudo = (valor: string) => ({
      element(el: { setAttribute(n: string, v: string): void }) {
        el.setAttribute('content', valor)
      },
    })

    const rw = new HTMLRewriter()
      .on('title', { element: (el) => el.setInnerContent(titulo) })
      .on('meta[property="og:title"]', conteudo(titulo))
      .on('meta[property="og:description"]', conteudo(descricao))
      .on('meta[name="theme-color"]', conteudo(escapar(empresa.cor_principal)))
      .on('head', {
        element(el: any) {
          el.append(`<meta property="og:url" content="${escapar(pagina)}">`, { html: true })
          el.append(`<meta name="description" content="${descricao}">`, { html: true })
          if (empresa.logo_url) {
            el.append(`<meta property="og:image" content="${escapar(empresa.logo_url)}">`, { html: true })
          }
        },
      })
    return rw.transform(resposta)
  } catch {
    return resposta
  }
}
