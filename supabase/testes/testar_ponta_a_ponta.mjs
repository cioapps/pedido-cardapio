// Teste ponta a ponta no Supabase REAL, imitando um lojista novo e um cliente.
// Cria uma conta temporária, faz tudo e apaga no final.
// Uso (na raiz): node supabase/testes/testar_ponta_a_ponta.mjs
// Precisa no .env da raiz: SUPABASE_ACCESS_TOKEN e SUPABASE_PROJECT_REF.
import { readFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const env = Object.fromEntries(readFileSync('.env', 'utf8').split(/\r?\n/).filter((l) => /^\w+=/.test(l))
  .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
const ref = env.SUPABASE_PROJECT_REF
const url = `https://${ref}.supabase.co`
const mgmt = { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json' }

const chaves = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: mgmt })).json()
const publica = chaves.find((k) => k.type === 'publishable').api_key
const secreta = chaves.find((k) => k.type === 'secret').api_key
const admin = createClient(url, secreta, { auth: { persistSession: false } })

let ok = 0, falhas = 0
const passo = async (nome, fn) => {
  try { const r = await fn(); ok++; console.log('  ✓', nome, r ?? ''); return r }
  catch (e) { falhas++; console.log('  ✗', nome, '\n     ', e.message ?? e); return null }
}
const garantir = (cond, msg) => { if (!cond) throw new Error(msg) }
const semErro = ({ data, error }) => { if (error) throw new Error(error.message); return data }

const sufixo = Date.now().toString(36)
const email = `teste-e2e-${sufixo}@exemplo.com`
const senha = `Senha-${sufixo}!`
const slug = `teste-e2e-${sufixo}`
const lojista = createClient(url, publica, { auth: { persistSession: false } })
const cliente = createClient(url, publica, { auth: { persistSession: false } })
let idEmpresa, idUsuario

console.log(`Conta temporária: ${email}\n`)
try {
  await passo('cadastro sem confirmação de e-mail já entra', async () => {
    const r = semErro(await lojista.auth.signUp({ email, password: senha }))
    garantir(r.session, 'signUp não devolveu sessão (confirmação de e-mail ligada?)')
    idUsuario = r.user.id
  })
  await passo('cria a loja (criar_empresa) com 7 dias de teste', async () => {
    idEmpresa = semErro(await lojista.rpc('criar_empresa', { p_nome_empresa: 'Teste E2E', p_slug_empresa: slug, p_telefone_whatsapp: '11999998888' }))
    const a = semErro(await lojista.rpc('minha_assinatura'))
    garantir(a.liberada && a.situacao === 'teste' && a.dias_restantes >= 6, JSON.stringify(a))
    return `loja ${idEmpresa}`
  })
  const idCategoria = await passo('cria categoria', async () =>
    semErro(await lojista.from('categorias').insert({ id_empresa: idEmpresa, nome_categoria: 'Lanches', ordem_exibicao: 1 }).select('id').single()).id)

  const urlFoto = await passo('envia foto do produto (Storage) e a foto abre', async () => {
    // PNG 1x1 válido
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64')
    const caminho = `${idEmpresa}/produtos/${Date.now()}.jpg`
    semErro(await lojista.storage.from('imagens').upload(caminho, png, { contentType: 'image/jpeg' }))
    const publicaUrl = lojista.storage.from('imagens').getPublicUrl(caminho).data.publicUrl
    const r = await fetch(publicaUrl)
    garantir(r.ok, `foto não abre: ${r.status}`)
    return publicaUrl
  })
  await passo('NÃO consegue enviar foto na pasta de outra loja', async () => {
    const { error } = await lojista.storage.from('imagens').upload(`1/produtos/invasao-${sufixo}.jpg`, Buffer.from('x'), { contentType: 'image/jpeg' })
    garantir(error, 'deveria ter sido bloqueado')
  })
  const idGrupo = await passo('cria grupo obrigatório com 2 opções', async () => {
    const g = semErro(await lojista.from('grupos_opcoes').insert({ id_empresa: idEmpresa, nome_grupo: 'Escolha o pão', minimo_selecao: 1, maximo_selecao: 1, ordem_exibicao: 1 }).select('id').single())
    semErro(await lojista.from('opcoes').insert([
      { id_empresa: idEmpresa, id_grupo_opcao: g.id, nome_opcao: 'Pão comum', preco_adicional: 0, ordem_exibicao: 1 },
      { id_empresa: idEmpresa, id_grupo_opcao: g.id, nome_opcao: 'Pão brioche', preco_adicional: 3, ordem_exibicao: 2 },
    ]))
    return g.id
  })
  const idProduto = await passo('cria produto com foto e grupo vinculado', async () => {
    const p = semErro(await lojista.from('produtos').insert({ id_empresa: idEmpresa, id_categoria: idCategoria, nome_produto: 'X-Teste', preco_produto: 20, foto_url: urlFoto, ordem_exibicao: 1 }).select('id').single())
    semErro(await lojista.rpc('salvar_grupos_do_produto', { p_id_produto: p.id, p_ids_grupos: [idGrupo] }))
    return p.id
  })
  const idBairro = await passo('cadastra bairro com taxa', async () =>
    semErro(await lojista.from('bairros_entrega').insert({ id_empresa: idEmpresa, nome_bairro: 'Centro', taxa_entrega: 5 }).select('id').single()).id)
  await passo('atualiza dados da loja (cor, mínimo, tempo)', async () => {
    semErro(await lojista.from('empresas').update({ cor_principal: '#2A9D8F', pedido_minimo: 10, tempo_entrega_minutos: 30 }).eq('id', idEmpresa))
  })
  await passo('cliente vê o cardápio público com foto e opções', async () => {
    const c = semErro(await cliente.rpc('obter_cardapio', { p_slug: slug }))
    const p = c.categorias[0].produtos[0]
    garantir(p.foto_url === urlFoto && p.grupos[0].opcoes.length === 2 && c.empresa.loja_disponivel !== false, JSON.stringify(p).slice(0, 200))
  })
  await passo('página do cardápio em define.ia.br abre com o nome da loja', async () => {
    const r = await fetch(`https://define.ia.br/${slug}`)
    const html = await r.text()
    garantir(r.ok && html.includes('Teste E2E'), `status ${r.status}`)
  })
  const opcaoBrioche = semErro(await admin.from('opcoes').select('id').eq('id_grupo_opcao', idGrupo).eq('nome_opcao', 'Pão brioche').single()).id
  await passo('cliente faz pedido: preço calculado no servidor (2x (20+3) + 5 = 51)', async () => {
    const r = semErro(await cliente.rpc('criar_pedido', { p_dados: {
      slug_empresa: slug, nome_cliente: 'Cliente E2E', telefone_cliente: '(11) 97777-6666',
      logradouro: 'Rua Teste', numero_endereco: '1', id_bairro_entrega: idBairro, forma_pagamento: 'pix',
      itens: [{ id_produto: idProduto, quantidade: 2, opcoes: [{ id_opcao: opcaoBrioche, quantidade: 1 }] }],
    } }))
    garantir(Number(r.valor_total) === 51 && r.numero_pedido === 1, JSON.stringify(r))
    return `pedido #${r.numero_pedido} R$ ${r.valor_total}`
  })
  await passo('lojista vê o pedido e aceita', async () => {
    const p = semErro(await lojista.from('pedidos').select('id, status_pedido').eq('id_empresa', idEmpresa).single())
    garantir(p.status_pedido === 'novo', p.status_pedido)
    semErro(await lojista.from('pedidos').update({ status_pedido: 'aceito' }).eq('id', p.id))
  })
  await passo('aba Vendas: resumo de hoje mostra o pedido', async () => {
    const hoje = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' })
    const r = semErro(await lojista.rpc('resumo_vendas', { p_inicio: hoje, p_fim: hoje }))
    garantir(r.pedidos === 1 && Number(r.faturamento) === 51 && r.mais_vendidos[0].nome === 'X-Teste', JSON.stringify(r).slice(0, 200))
  })
  await passo('assinatura vencida bloqueia novos pedidos', async () => {
    semErro(await admin.from('empresas').update({ situacao_assinatura: 'teste', assinatura_valida_ate: new Date(Date.now() - 60_000).toISOString() }).eq('id', idEmpresa))
    const { error } = await cliente.rpc('criar_pedido', { p_dados: {
      slug_empresa: slug, nome_cliente: 'X', telefone_cliente: '11977776666', logradouro: 'R', numero_endereco: '1',
      id_bairro_entrega: idBairro, forma_pagamento: 'pix', itens: [{ id_produto: idProduto, quantidade: 1, opcoes: [{ id_opcao: opcaoBrioche, quantidade: 1 }] }],
    } })
    garantir(error && error.message.includes('indisponível'), error?.message ?? 'pedido entrou')
    const a = semErro(await lojista.rpc('minha_assinatura'))
    garantir(a.liberada === false, 'app deveria ver bloqueio')
  })
} finally {
  // limpeza: apaga fotos, loja (cascata) e usuário
  if (idEmpresa) {
    const { data: arquivos } = await admin.storage.from('imagens').list(`${idEmpresa}/produtos`)
    if (arquivos?.length) await admin.storage.from('imagens').remove(arquivos.map((a) => `${idEmpresa}/produtos/${a.name}`))
    await admin.from('empresas').delete().eq('id', idEmpresa)
  }
  if (idUsuario) await admin.auth.admin.deleteUser(idUsuario)
  console.log('\nLimpeza feita (conta, loja e fotos de teste apagadas).')
}
console.log(`\n${ok} ok, ${falhas} falha(s)`)
process.exit(falhas ? 1 : 0)
