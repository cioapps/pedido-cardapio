// Valida migrations + seed + regras de negócio num Postgres em memória (PGlite),
// simulando o que o Supabase fornece (auth, storage, roles, publication).
// Rodar na raiz: npm run test:db
import { PGlite } from '@electric-sql/pglite'
import { readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const raiz = fileURLToPath(new URL('../..', import.meta.url))
const ler = (p) => readFileSync(`${raiz}/${p}`, 'utf8')
const db = new PGlite()

const STUB = `
create role anon nologin; create role authenticated nologin;
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
create schema auth; grant usage on schema auth to anon, authenticated;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated;
create schema storage; grant usage on schema storage to anon, authenticated;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid default gen_random_uuid() primary key, bucket_id text, name text);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
create publication supabase_realtime;
`

let ok = 0, falhas = 0
const teste = async (nome, fn) => {
  try { await fn(); ok++; console.log('  ✓', nome) }
  catch (e) { falhas++; console.log('  ✗', nome, '\n     ', e.message) }
}
const espera = (cond, msg) => { if (!cond) throw new Error(msg) }
const esperaErro = async (fn, trecho) => {
  try { await fn() } catch (e) {
    if (trecho && !e.message.includes(trecho)) throw new Error(`erro inesperado: ${e.message}`)
    return e.message
  }
  throw new Error('deveria ter falhado')
}

const comoAnon = async (sql, params) => {
  await db.exec(`set role anon; select set_config('request.jwt.claim.sub', '', false);`)
  try { return await db.query(sql, params) } finally { await db.exec('reset role') }
}
const comoUsuario = async (uid, sql, params) => {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false);`)
  try { return await db.query(sql, params) } finally { await db.exec('reset role') }
}

console.log('Aplicando migrations...')
await db.exec(STUB)
for (const arquivo of readdirSync(`${raiz}/supabase/migrations`).filter((a) => a.endsWith('.sql')).sort()) {
  await db.exec(ler(`supabase/migrations/${arquivo}`).replace(/create extension if not exists pgcrypto;/i, ''))
}
await db.exec(ler('supabase/seed.sql'))
console.log('OK\n')

const A = '11111111-1111-1111-1111-111111111111'
const B = '22222222-2222-2222-2222-222222222222'
await db.exec(`insert into auth.users values ('${A}','a@x.com'),('${B}','b@x.com');
  insert into public.usuarios_empresa (id_empresa, id_usuario_auth, papel)
  select id, '${A}', 'dono' from public.empresas where slug_empresa = 'lanche-exemplo';`)

const ids = (await db.query(`
  select (select id from produtos where nome_produto='X-Burger') x_burger,
         (select id from produtos where nome_produto='X-Tudo') x_tudo,
         (select id from produtos where nome_produto='Refrigerante lata') refri,
         (select id from opcoes where nome_opcao='Pão australiano') pao_aus,
         (select id from opcoes where nome_opcao='Ao ponto') ao_ponto,
         (select id from opcoes where nome_opcao='Bacon') bacon,
         (select id from opcoes where nome_opcao='Cheddar cremoso') molho_cheddar,
         (select id from bairros_entrega where nome_bairro='Centro') centro`)).rows[0]

const pedidoBase = (itens, extra = {}) => ({
  slug_empresa: 'lanche-exemplo', nome_cliente: 'João', telefone_cliente: '(11) 98888-7777',
  logradouro: 'Rua A', numero_endereco: '10', id_bairro_entrega: ids.centro,
  forma_pagamento: 'dinheiro', troco_para: 100, itens, ...extra,
})
const criar = (dados) => comoAnon('select criar_pedido($1::jsonb) r', [JSON.stringify(dados)])

console.log('Cardápio público')
await teste('anon lê cardápio completo via obter_cardapio', async () => {
  const r = (await comoAnon(`select obter_cardapio('lanche-exemplo') c`)).rows[0].c
  espera(r.categorias.length === 3, 'esperava 3 categorias')
  const xb = r.categorias[0].produtos.find((p) => p.nome_produto === 'X-Burger')
  espera(xb.grupos.length === 4, 'X-Burger deveria ter 4 grupos')
  espera(r.bairros.length === 3 && r.empresa.loja_aberta === true, 'bairros/loja')
})
await teste('slug inexistente retorna null', async () => {
  const r = (await comoAnon(`select obter_cardapio('nao-existe') c`)).rows[0].c
  espera(r === null, 'deveria ser null')
})
await teste('anon NÃO lê pedidos nem clientes', async () => {
  await esperaErro(() => comoAnon('select * from pedidos'), 'permission denied')
  await esperaErro(() => comoAnon('select * from clientes'), 'permission denied')
})
await teste('anon NÃO insere produto', async () => {
  await esperaErro(() => comoAnon(`insert into produtos (id_empresa,id_categoria,nome_produto) values (1,1,'hack')`))
})

console.log('\ncriar_pedido')
let codigo
await teste('pedido válido: preço recalculado no servidor', async () => {
  const r = (await criar(pedidoBase([
    { id_produto: ids.x_burger, quantidade: 2, preco_unitario: 0.01, observacao_item: 'sem cebola',
      opcoes: [{ id_opcao: ids.pao_aus, quantidade: 1 }, { id_opcao: ids.ao_ponto, quantidade: 1 }, { id_opcao: ids.bacon, quantidade: 2 }] },
  ]))).rows[0].r
  // (22.90 + 2 pão + 2x4 bacon) * 2 = 65.80 + 5 taxa = 70.80
  espera(Number(r.valor_total) === 70.8, `total ${r.valor_total} != 70.80`)
  espera(r.numero_pedido === 1, 'numero 1')
  codigo = r.codigo_acompanhamento
})
await teste('numeração sequencial por loja', async () => {
  const r = (await criar(pedidoBase([{ id_produto: ids.x_tudo, quantidade: 1,
    opcoes: [{ id_opcao: ids.pao_aus, quantidade: 1 }] }], { forma_pagamento: 'pix', troco_para: null }))).rows[0].r
  espera(r.numero_pedido === 2, 'numero 2')
})
await teste('falta grupo obrigatório -> erro', async () => {
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.x_burger, quantidade: 1, opcoes: [{ id_opcao: ids.pao_aus }] }])), 'Ponto da carne')
})
await teste('opção de grupo não vinculado ao produto -> erro', async () => {
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.x_tudo, quantidade: 1,
    opcoes: [{ id_opcao: ids.pao_aus }, { id_opcao: ids.ao_ponto }] }])), 'Opção indisponível')
})
await teste('acima do máximo do grupo -> erro', async () => {
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.x_tudo, quantidade: 1,
    opcoes: [{ id_opcao: ids.pao_aus }, { id_opcao: ids.molho_cheddar, quantidade: 3 }] }])), 'no máximo')
})
await teste('abaixo do pedido mínimo -> erro', async () => {
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.refri, quantidade: 1 }])), 'pedido mínimo')
})
await teste('troco menor que total -> erro', async () => {
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.refri, quantidade: 5 }], { troco_para: 10 })), 'troco')
})
await teste('erro no meio desfaz tudo (sem pedido órfão)', async () => {
  const n = (await db.query('select count(*)::int n from pedidos')).rows[0].n
  espera(n === 2, `esperava 2 pedidos, há ${n}`)
  const num = (await db.query(`select ultimo_numero_pedido n from empresas where slug_empresa='lanche-exemplo'`)).rows[0].n
  espera(num === 2, `contador ${num}`)
})
await teste('loja fechada -> erro', async () => {
  await db.exec(`update empresas set aberta_manual=false where slug_empresa='lanche-exemplo'`)
  try {
    await esperaErro(() => criar(pedidoBase([{ id_produto: ids.refri, quantidade: 5 }])), 'fechada')
  } finally { await db.exec(`update empresas set aberta_manual=true where slug_empresa='lanche-exemplo'`) }
})
await teste('cliente salvo com telefone só dígitos', async () => {
  const r = (await db.query('select telefone_cliente from clientes')).rows
  espera(r.length === 1 && r[0].telefone_cliente === '11988887777', JSON.stringify(r))
})
await teste('consultar_pedido pelo código (anon)', async () => {
  const r = (await comoAnon('select consultar_pedido($1::uuid) p', [codigo])).rows[0].p
  espera(r.numero_pedido === 1 && r.itens[0].opcoes.length === 3, JSON.stringify(r).slice(0, 200))
})

console.log('\nMultiempresa (RLS)')
await teste('lojista A vê os pedidos da loja dele', async () => {
  const r = await comoUsuario(A, 'select id from pedidos')
  espera(r.rows.length === 2, `viu ${r.rows.length}`)
})
await teste('lojista B (sem loja) não vê nada', async () => {
  espera((await comoUsuario(B, 'select id from pedidos')).rows.length === 0, 'B viu pedidos')
  espera((await comoUsuario(B, 'select id from clientes')).rows.length === 0, 'B viu clientes')
})
await teste('lojista A muda status, mas não o valor', async () => {
  await comoUsuario(A, `update pedidos set status_pedido='aceito' where numero_pedido=1`)
  await esperaErro(() => comoUsuario(A, `update pedidos set valor_total=1 where numero_pedido=1`), 'permission denied')
})
await teste('lojista B não altera pedido da loja A', async () => {
  await comoUsuario(B, `update pedidos set status_pedido='cancelado' where numero_pedido=1`)
  const s = (await db.query('select status_pedido s from pedidos where numero_pedido=1')).rows[0].s
  espera(s === 'aceito', `status virou ${s}`)
})
await teste('lojista B cria loja própria via criar_empresa', async () => {
  const id = (await comoUsuario(B, `select criar_empresa('Pizza do B','pizza-do-b','11 97777-6666') id`)).rows[0].id
  espera(id, 'sem id')
  await esperaErro(() => comoUsuario(B, `select criar_empresa('Outra','lanche-exemplo','')`), 'já está em uso')
})
await teste('lojista B cadastra categoria só na loja dele', async () => {
  const idB = (await db.query(`select id from empresas where slug_empresa='pizza-do-b'`)).rows[0].id
  await comoUsuario(B, `insert into categorias (id_empresa, nome_categoria) values (${idB}, 'Pizzas')`)
  await esperaErro(() => comoUsuario(B, `insert into categorias (id_empresa, nome_categoria) values (1, 'Hack')`), 'row-level security')
})
await teste('lojista vê produtos inativos da própria loja; público não', async () => {
  await db.exec(`update produtos set ativo=false where nome_produto='Onion rings'`)
  const lojista = (await comoUsuario(A, `select id from produtos where nome_produto='Onion rings'`)).rows.length
  const publico = (await comoAnon(`select id from produtos where nome_produto='Onion rings'`)).rows.length
  espera(lojista === 1 && publico === 0, `lojista ${lojista} publico ${publico}`)
})
await teste('salvar_grupos_do_produto substitui vínculos', async () => {
  await comoUsuario(A, `select salvar_grupos_do_produto(${ids.x_tudo}, array[(select id from grupos_opcoes where nome_grupo='Adicionais')]::bigint[])`)
  const n = (await db.query(`select count(*)::int n from produtos_grupos_opcoes where id_produto=${ids.x_tudo}`)).rows[0].n
  espera(n === 1, `ficaram ${n}`)
  await esperaErro(() => comoUsuario(B, `select salvar_grupos_do_produto(${ids.x_tudo}, '{}')`), 'não encontrado')
})

console.log('\nHorários')
await teste('horário que vira a noite (18h-02h)', async () => {
  await db.exec(`update empresas set usar_horarios=true, fuso_horario='UTC' where id=1;
    delete from horarios_funcionamento where id_empresa=1;
    insert into horarios_funcionamento (id_empresa,dia_semana,hora_abertura,hora_fechamento)
    select 1, d, '18:00', '02:00' from generate_series(0,6) d;`)
  const h = (await db.query(`select extract(hour from now() at time zone 'UTC')::int h`)).rows[0].h
  const aberta = (await db.query('select loja_esta_aberta(1) a')).rows[0].a
  espera(aberta === (h >= 18 || h < 2), `hora ${h} aberta=${aberta}`)
  await db.exec(`update empresas set usar_horarios=false where id=1`)
})

console.log('\nMódulos por loja')
const ADMIN = '33333333-3333-3333-3333-333333333333'
await db.exec(`insert into auth.users values ('${ADMIN}','admin@x.com');
  insert into public.administradores_sistema (id_usuario_auth) values ('${ADMIN}');`)
const idLoja = (await db.query(`select id from empresas where slug_empresa='lanche-exemplo'`)).rows[0].id

await teste('lojista NÃO liga/desliga módulos', async () => {
  await esperaErro(() => comoUsuario(A, `update empresas set modulo_whatsapp_ativo=true where id=${idLoja}`), 'permission denied')
  await esperaErro(() => comoUsuario(A, `select definir_modulos_empresa(${idLoja}, true, true)`), 'Apenas administradores')
})
await teste('administrador lista lojas e define módulos', async () => {
  const lojas = (await comoUsuario(ADMIN, 'select * from listar_empresas_admin()')).rows
  espera(lojas.length >= 2, `listou ${lojas.length}`)
  await comoUsuario(ADMIN, `select definir_modulos_empresa(${idLoja}, false, true)`)
  const e = (await db.query(`select modulo_cardapio_ativo c, modulo_whatsapp_ativo w from empresas where id=${idLoja}`)).rows[0]
  espera(e.c === false && e.w === true, JSON.stringify(e))
})
await teste('cardápio desligado: obter_cardapio avisa e criar_pedido recusa', async () => {
  const c = (await comoAnon(`select obter_cardapio('lanche-exemplo') c`)).rows[0].c
  espera(c.empresa.cardapio_ativo === false, 'cardapio_ativo deveria ser false')
  await esperaErro(() => criar(pedidoBase([{ id_produto: ids.refri, quantidade: 5 }])), 'apenas pelo WhatsApp')
})

console.log('\nWhatsApp: rascunhos')
await db.exec(`
  insert into conexoes_whatsapp (id_empresa, nome_instancia, token_instancia) values (${idLoja}, 'loja-1', 'token-secreto');
  insert into conversas_whatsapp (id_empresa, chat_id, nome_contato, telefone_contato)
    values (${idLoja}, '5511977776666@s.whatsapp.net', 'Maria', '5511977776666');
  insert into mensagens_whatsapp (id_empresa, id_conversa, id_mensagem_externa, texto_mensagem)
    values (${idLoja}, 1, 'msg-1', 'quero 1 refri');
  insert into rascunhos_pedido (id_empresa, id_conversa, status_rascunho) values (${idLoja}, 1, 'pronto');`)
const dadosWhats = {
  nome_cliente: 'Maria', logradouro: 'Rua B', numero_endereco: '20', id_bairro_entrega: ids.centro,
  forma_pagamento: 'pix', itens: [{ id_produto: ids.refri, quantidade: 1, preco_unitario: 0.01 }],
}
const confirmar = (uid, id, dados = dadosWhats) =>
  comoUsuario(uid, 'select confirmar_rascunho($1, $2::jsonb) r', [id, JSON.stringify(dados)])

await teste('token da instância NÃO é legível pelo lojista', async () => {
  await esperaErro(() => comoUsuario(A, 'select token_instancia from conexoes_whatsapp'), 'permission denied')
  await esperaErro(() => comoUsuario(A, 'select segredo_webhook from conexoes_whatsapp'), 'permission denied')
  const r = (await comoUsuario(A, 'select status_conexao from conexoes_whatsapp')).rows
  espera(r.length === 1, 'lojista deveria ver o status')
  espera((await comoUsuario(B, 'select status_conexao from conexoes_whatsapp')).rows.length === 0, 'B viu conexão de A')
})
await teste('anon não vê conversas nem confirma rascunho', async () => {
  await esperaErro(() => comoAnon('select * from mensagens_whatsapp'), 'permission denied')
  await esperaErro(() => comoAnon(`select confirmar_rascunho(1, '{}'::jsonb)`), 'permission denied')
})
await teste('lojista B não confirma rascunho da loja A', async () => {
  await esperaErro(() => confirmar(B, 1), 'não encontrado')
})
await teste('confirmar: pedido origem whatsapp, aceito, telefone da conversa, preço do servidor', async () => {
  const r = (await confirmar(A, 1)).rows[0].r
  const p = (await db.query(`select * from pedidos where id=${r.id_pedido}`)).rows[0]
  espera(p.origem_pedido === 'whatsapp' && p.status_pedido === 'aceito', `${p.origem_pedido}/${p.status_pedido}`)
  espera(p.telefone_cliente === '5511977776666', `telefone ${p.telefone_cliente}`)
  // 6,00 do refri (abaixo do mínimo de 20: no WhatsApp o lojista decide) + 5 de taxa
  espera(Number(p.valor_total) === 11, `total ${p.valor_total}`)
  espera(Number(p.id_conversa_whatsapp) === 1, 'sem vínculo com a conversa')
  const rs = (await db.query('select status_rascunho s, id_pedido from rascunhos_pedido where id=1')).rows[0]
  espera(rs.s === 'confirmado' && Number(rs.id_pedido) === Number(r.id_pedido), JSON.stringify(rs))
})
await teste('rascunho já confirmado não confirma de novo', async () => {
  await esperaErro(() => confirmar(A, 1), 'já foi confirmado')
})
await teste('só um rascunho aberto por conversa', async () => {
  await db.exec(`insert into rascunhos_pedido (id_empresa, id_conversa) values (${idLoja}, 1)`)
  await esperaErro(() => db.exec(`insert into rascunhos_pedido (id_empresa, id_conversa) values (${idLoja}, 1)`), 'duplicate')
})
await teste('lojista descarta, mas não muda para outro status', async () => {
  const id = (await db.query(`select id from rascunhos_pedido where status_rascunho='montando'`)).rows[0].id
  await esperaErro(() => comoUsuario(A, `update rascunhos_pedido set status_rascunho='confirmado' where id=${id}`), 'row-level security')
  await comoUsuario(B, `update rascunhos_pedido set status_rascunho='descartado' where id=${id}`)
  espera((await db.query(`select status_rascunho s from rascunhos_pedido where id=${id}`)).rows[0].s === 'montando', 'B descartou')
  await comoUsuario(A, `update rascunhos_pedido set status_rascunho='descartado' where id=${id}`)
  espera((await db.query(`select status_rascunho s from rascunhos_pedido where id=${id}`)).rows[0].s === 'descartado', 'A não descartou')
})
await teste('módulo WhatsApp desligado bloqueia confirmação', async () => {
  await comoUsuario(ADMIN, `select definir_modulos_empresa(${idLoja}, true, false)`)
  await db.exec(`insert into rascunhos_pedido (id_empresa, id_conversa) values (${idLoja}, 1)`)
  const id = (await db.query(`select id from rascunhos_pedido where status_rascunho='montando'`)).rows[0].id
  await esperaErro(() => confirmar(A, id), 'desativado')
})
await teste('inserir_pedido interno não é acessível de fora', async () => {
  await esperaErro(() => comoUsuario(A, `select privado.inserir_pedido(1, '{}'::jsonb, 'whatsapp', false, 'aceito')`), 'permission denied')
})

console.log('\nAssinatura')
const pedidoSimples = () => criar(pedidoBase([{ id_produto: ids.refri, quantidade: 5, opcoes: [] }], { troco_para: null }))
await teste('loja nova ganha teste de 7 dias e está liberada', async () => {
  const nova = (await db.query(`select situacao_assinatura s, assinatura_valida_ate > now() + interval '6 days' prazo,
    assinatura_liberada(id) lib from empresas order by id desc limit 1`)).rows[0]
  espera(nova.s === 'teste' && nova.prazo && nova.lib, JSON.stringify(nova))
})
await teste('lojista vê a própria assinatura pelo relógio do servidor', async () => {
  const r = (await comoUsuario(A, 'select minha_assinatura() r')).rows[0].r
  espera(r.liberada === true && r.dias_restantes >= 6, JSON.stringify(r))
})
await teste('lojista NÃO altera a própria assinatura', async () => {
  await esperaErro(() => comoUsuario(A, `update empresas set situacao_assinatura='ativa', assinatura_valida_ate=null where id=${idLoja}`),
    'permission denied')
  await esperaErro(() => comoUsuario(A, `select definir_assinatura_empresa(${idLoja}, 'ativa', null)`), 'Apenas administradores')
})
await teste('bloqueada: cardápio avisa e pedido é recusado', async () => {
  await comoUsuario(ADMIN, `select definir_assinatura_empresa(${idLoja}, 'bloqueada', null)`)
  const c = (await comoAnon(`select obter_cardapio('lanche-exemplo') c`)).rows[0].c
  espera(c.empresa.loja_disponivel === false, 'loja_disponivel deveria ser false')
  await esperaErro(pedidoSimples, 'indisponível')
  espera((await comoUsuario(A, 'select minha_assinatura() r')).rows[0].r.liberada === false, 'deveria estar bloqueada')
})
await teste('teste vencido também bloqueia', async () => {
  await comoUsuario(ADMIN, `select definir_assinatura_empresa(${idLoja}, 'teste', now() - interval '1 hour')`)
  await esperaErro(pedidoSimples, 'indisponível')
})
await teste('administrador ativa e o pedido volta a entrar', async () => {
  await comoUsuario(ADMIN, `select definir_assinatura_empresa(${idLoja}, 'ativa', now() + interval '30 days')`)
  const lojas = (await comoUsuario(ADMIN, 'select * from listar_empresas_admin()')).rows
  const l = lojas.find((x) => Number(x.id) === Number(idLoja))
  espera(l.assinatura_liberada === true && l.email_dono === 'a@x.com', JSON.stringify(l))
  const r = (await pedidoSimples()).rows[0].r
  espera(r.numero_pedido > 0, 'pedido não entrou')
})

console.log('\nPush e vendas')
const TOKEN = 'token-fcm-de-teste-com-mais-de-vinte-caracteres'
await teste('lojista registra o celular; anon não; ninguém lê a tabela direto', async () => {
  await comoUsuario(A, `select registrar_dispositivo('${TOKEN}')`)
  await comoUsuario(A, `select registrar_dispositivo('${TOKEN}')`) // repetir não duplica
  const n = (await db.query(`select count(*)::int n, min(id_empresa) e from dispositivos_lojista`)).rows[0]
  espera(n.n === 1 && Number(n.e) === Number(idLoja), JSON.stringify(n))
  await esperaErro(() => comoAnon(`select registrar_dispositivo('${TOKEN}')`), 'permission denied')
  await esperaErro(() => comoUsuario(A, 'select * from dispositivos_lojista'), 'permission denied')
})
await teste('pedido novo chama a função de aviso (pg_net simulado)', async () => {
  await db.exec(`create schema net;
    create table net.chamadas (url text, body jsonb, headers jsonb);
    create function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int) returns bigint
      language sql as $$ insert into net.chamadas values (url, body, headers) returning 1::bigint $$;
    insert into privado.configuracoes values ('url_funcoes', 'https://x.supabase.co/functions/v1'), ('segredo_push', 's3gr3d0');`)
  const r = (await pedidoSimples()).rows[0].r
  const c = (await db.query('select * from net.chamadas')).rows
  espera(c.length === 1, `chamadas: ${c.length}`)
  espera(c[0].url.endsWith('/notificar-pedido') && c[0].headers['x-segredo'] === 's3gr3d0', JSON.stringify(c[0]))
  espera(c[0].body.titulo === `Novo pedido #${r.numero_pedido}` && c[0].body.texto.includes('R$ ' + Number(r.valor_total).toFixed(2).replace('.', ',')), JSON.stringify(c[0].body))
})
await teste('falha no aviso não impede o pedido', async () => {
  await db.exec(`create or replace function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int)
    returns bigint language plpgsql as $$ begin raise exception 'rede fora'; end $$;`)
  const r = (await pedidoSimples()).rows[0].r
  espera(r.numero_pedido > 0, 'pedido não entrou')
})
await teste('resumo_vendas: totais, dias, mais vendidos e cancelados fora', async () => {
  await comoUsuario(A, `update pedidos set status_pedido='cancelado' where id = (select max(id) from pedidos where id_empresa=${idLoja})`)
  const r = (await comoUsuario(A, `select resumo_vendas(current_date - 6, current_date) r`)).rows[0].r
  const esperado = (await db.query(`select coalesce(sum(valor_total),0)::float t, count(*)::int n from pedidos
     where id_empresa=${idLoja} and status_pedido <> 'cancelado'`)).rows[0]
  espera(Number(r.faturamento) === esperado.t && r.pedidos === esperado.n, `${r.faturamento}/${r.pedidos} vs ${JSON.stringify(esperado)}`)
  espera(r.cancelados >= 1, 'cancelado deveria contar')
  espera(r.por_dia.length === 7, `por_dia ${r.por_dia.length}`)
  espera(r.mais_vendidos.length > 0 && r.por_pagamento.length > 0, 'listas vazias')
})
await teste('resumo_vendas só da própria loja; anon não acessa', async () => {
  const r = (await comoUsuario(B, `select resumo_vendas(current_date - 6, current_date) r`)).rows[0].r
  espera(r.pedidos === 0, 'B viu pedidos de A')
  await esperaErro(() => comoAnon(`select resumo_vendas(current_date, current_date)`), 'permission denied')
})
await teste('ao sair, remove o celular', async () => {
  await comoUsuario(A, `select remover_dispositivo('${TOKEN}')`)
  espera((await db.query('select count(*)::int n from dispositivos_lojista')).rows[0].n === 0, 'não removeu')
})

console.log(`\n${ok} ok, ${falhas} falha(s)`)
process.exit(falhas ? 1 : 0)
