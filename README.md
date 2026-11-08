# Cardápio Online

Sistema de pedidos para lanchonetes (multiempresa). Cada loja tem um link próprio
(`seudominio.com.br/nome-da-loja`) que é enviado no WhatsApp dos clientes. O cliente
monta o pedido com seleções e adicionais, e o pedido chega na hora no app do lojista,
que imprime na impressora térmica da cozinha.

```
Cliente (celular) ──► Cardápio web ──► Supabase (criar_pedido) ──► Realtime ──► App do lojista ──► Impressora térmica
                       Cloudflare Pages                                          Flutter (Android)   Bluetooth / Rede
```

## Assinatura (bloqueio básico)

Cada loja tem `situacao_assinatura` (`teste` / `ativa` / `bloqueada`) e `assinatura_valida_ate`.
Loja nova ganha **7 dias de teste**. Vencida ou bloqueada: o cardápio mostra "indisponível", nenhum pedido entra
(trigger no banco), o app mostra a tela de bloqueio e a IA do WhatsApp para.
No **/admin** você usa "+7 dias teste", "Ativar +30 dias", "Ativa sem prazo" e "Bloquear".
O número do botão "Ativar pelo WhatsApp" do app vem de `WHATSAPP_SUPORTE` em `apps/app_lojista/env.json`.

## Módulos por loja

Cada loja pode usar **um ou os dois** módulos. Quem liga e desliga é o administrador do sistema, em `/admin`.

| Módulo | O que faz |
|---|---|
| **Cardápio online** | Link público da loja; o cliente monta o pedido sozinho |
| **WhatsApp com IA** | O lojista conversa normalmente no WhatsApp; a IA (Claude) acompanha a conversa, inclusive áudios, monta o pedido com o cardápio cadastrado e o deixa na aba **WhatsApp** do app para o lojista conferir e tocar em **Confirmar e imprimir** |

Nos dois casos o cadastro do cardápio, os bairros, a lista de pedidos e a impressão são os mesmos.

```
Cliente ⇄ Lojista (WhatsApp) ──► uazapiGO (webhook) ──► Edge Function whatsapp-webhook ──► Claude
                                                                     │ rascunhos_pedido (Realtime)
                                                                     ▼
                                              App: aba WhatsApp → Confirmar e imprimir → pedido normal
```

**Para tornar alguém administrador**, depois que a pessoa criar a conta (pelo app):

```sql
insert into public.administradores_sistema (id_usuario_auth)
select id from auth.users where email = 'SEU_EMAIL';
```

## Estrutura do monorepo

| Pasta | O que é |
|---|---|
| [`supabase/`](supabase) | Banco: migrations (tabelas, RLS, funções), seed com loja de exemplo e **Edge Functions** do WhatsApp |
| [`apps/web/`](apps/web) | React + Vite + Tailwind: **cardápio público** (`/:slug`) e **administração** (`/admin`) |
| [`apps/app_lojista/`](apps/app_lojista) | Flutter (Android): **tudo do lojista** — criar conta e loja, cardápio, opções, bairros, horários, WhatsApp, pedidos em tempo real e impressão |

## Banco de dados (Supabase)

Colunas em português, `snake_case`, chaves `bigint` com autoincremento (`generated always as identity`).

| Tabela | Para que serve |
|---|---|
| `empresas` | Lojas (nome, `slug_empresa` do link, cor, pedido mínimo, aberta/fechada) |
| `usuarios_empresa` | Vincula o usuário do Supabase Auth à loja (`dono` / `funcionario`) |
| `horarios_funcionamento` | Horários por dia da semana (opcional) |
| `categorias`, `produtos` | O cardápio |
| `grupos_opcoes`, `opcoes` | Seleções e adicionais (ex.: “Escolha o pão” mín 1/máx 1; “Adicionais” mín 0/máx 10) |
| `produtos_grupos_opcoes` | Quais grupos aparecem em cada produto (grupos são reutilizáveis) |
| `bairros_entrega` | Bairros atendidos e taxa de entrega |
| `clientes` | Clientes por loja (identificados pelo telefone) |
| `pedidos`, `itens_pedido`, `itens_pedido_opcoes` | Pedidos com cópia de nomes e preços do momento da compra (`origem_pedido`: cardápio ou WhatsApp) |
| `administradores_sistema` | Quem administra o sistema e liga os módulos das lojas |
| `conexoes_whatsapp` | Instância uazapiGO de cada loja (o token fica invisível para o lojista) |
| `conversas_whatsapp`, `mensagens_whatsapp` | Conversas acompanhadas pela IA (mensagens apagadas após 30 dias) |
| `rascunhos_pedido` | O pedido que a IA está montando, com pendências, até o lojista confirmar ou descartar |

**Segurança:** RLS em todas as tabelas. O público só lê o cardápio ativo; cada lojista só acessa a própria loja.
Pedidos são criados só pelas funções `criar_pedido` (cardápio) e `confirmar_rascunho` (WhatsApp), que usam a mesma
lógica interna e **recalculam todos os preços no servidor**, validando bairro e mínimo/máximo de cada grupo.

Funções (RPC): `obter_cardapio`, `criar_pedido`, `consultar_pedido`, `criar_empresa`,
`salvar_grupos_do_produto`, `loja_esta_aberta`, `confirmar_rascunho`, `definir_modulos_empresa`,
`listar_empresas_admin`, `e_administrador`.

### Testes

```bash
npm test
```

Roda os testes do banco (Postgres em memória com as migrations reais) e as regras da IA.

Avaliar a IA com as conversas de exemplo de `supabase/testes/conversas/` (chama a API do Claude, tem custo de alguns centavos):

```bash
ANTHROPIC_API_KEY=sua-chave npm run avaliar:ia
```

### Aplicar no Supabase

Com a [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
supabase link --project-ref SEU_PROJECT_REF
```

```bash
supabase db push
```

```bash
psql "$SUPABASE_DB_URL" -f supabase/seed.sql
```

Ou cole os arquivos de `supabase/migrations/` (em ordem) e depois `supabase/seed.sql` no SQL Editor do painel.

Depois de criar sua conta pelo app, vincule-a à loja de exemplo (opcional) com o SQL que está no topo de `seed.sql`.

### Edge Functions do WhatsApp

```bash
cp supabase/functions/.env.example supabase/functions/.env   # preencha uazapi, Anthropic e (opcional) OpenAI
```

```bash
supabase secrets set --env-file supabase/functions/.env
```

```bash
supabase functions deploy whatsapp-conexao
```

```bash
supabase functions deploy whatsapp-webhook --no-verify-jwt
```

O webhook é configurado sozinho na uazapi quando o lojista conecta o número no app (Loja → WhatsApp com IA).
A IA usa `claude-opus-5-5` por padrão; para reduzir custo, defina `MODELO_IA=claude-sonnet-5-5` e compare
com `npm run avaliar:ia`.

## Web (cardápio + admin)

```bash
cp apps/web/.env.example apps/web/.env.local   # preencha URL e chave pública do Supabase
npm install
npm run dev
```

- Cardápio de exemplo: http://localhost:5173/lanche-exemplo
- Administração (lojas, módulos e assinatura): http://localhost:5173/admin

O lojista não usa a web: todo o cadastro fica no app Android.

### Deploy na Cloudflare Pages (define.ia.br)

Projeto Pages **define-cardapio** (conta CioApps), domínio **https://define.ia.br** (e `www.define.ia.br`).
O link de cada loja é `https://define.ia.br/<slug-da-loja>`.

Publicar uma nova versão (na raiz, com `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID` no `.env`):

```bash
npm run deploy:web
```

- O build usa `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` de `apps/web/.env.local`.
- A function `functions/[slug].ts` (preview do link no WhatsApp com nome e logo da loja) usa `SUPABASE_URL` /
  `SUPABASE_ANON_KEY` de `apps/web/wrangler.toml` (são públicas).
- No Supabase, Authentication → URL Configuration já aponta para `https://define.ia.br/admin`.
- Os registros DNS de `define.ia.br` e `www` são CNAME (com proxy) para `define-cardapio.pages.dev`.

## App do lojista (Flutter, Android)

```bash
cp apps/app_lojista/env.example.json apps/app_lojista/env.json   # preencha
cd apps/app_lojista && flutter run --dart-define-from-file=env.json
```

No Windows, se o PowerShell bloquear o `npm`, use `npm.cmd run app:run`.

Barra inferior com 4 abas:
- **Pedidos**: Novos / WhatsApp / Preparo / Entrega / Finalizados, ao vivo, alarme em loop enquanto houver pedido novo, abrir/fechar a loja
- **Cardápio**: categorias e produtos (foto pela galeria ou câmera), grupos de opções e adicionais, ordem com setas
- **Loja**: link do cardápio (compartilhar/copiar), dados, logo e cor, horários, bairros e taxas, WhatsApp com IA (código de pareamento ou QR Code)
- **Ajustes**: impressora e conta

Cadastro direto no app (sem confirmação de e-mail) → cria a loja → 7 dias de teste.

### Aviso de pedido com o app fechado (push)
Pedido novo (ou rascunho do WhatsApp pronto) dispara um gatilho no banco (`0006_push_e_vendas.sql`, via pg_net)
que chama a Edge Function `notificar-pedido`, que envia push pelo Firebase com um alarme de ~16 s
(canal `pedidos_alarme_v1`, som `res/raw/alerta_longo.wav`). Sem o Firebase configurado o app funciona normalmente,
só sem esse aviso.

Configurar uma vez:
1. Criar projeto no [Firebase](https://console.firebase.google.com) e adicionar um app Android com o pacote `com.cioapps.cardapio`.
2. Baixar o `google-services.json` para `apps/app_lojista/android/app/` (fora do Git).
3. Em Configurações do projeto → Contas de serviço → **Gerar nova chave privada** (JSON).
4. Secrets da função: `FIREBASE_SERVICE_ACCOUNT` (conteúdo do JSON numa linha) e `PUSH_SEGREDO` (o mesmo valor gravado em
   `privado.configuracoes`, chave `segredo_push`), e `supabase functions deploy notificar-pedido --no-verify-jwt`.

### Vendas
A aba **Vendas** usa a função `resumo_vendas(inicio, fim)`: faturamento (sem cancelados), pedidos, ticket médio,
comparação com o período anterior, vendas por dia/hora, mais vendidos e formas de pagamento.

### Impressora
ESC/POS por **Bluetooth** (pareie antes no Android; PIN costuma ser `0000` ou `1234`) ou **rede** (IP:9100), papel 58 ou 80 mm.
Testada para mini impressoras portáteis de 58 mm (tipo PT-210): o app pede a permissão "Dispositivos próximos" e
reconecta sozinho se a impressora tiver desligado para poupar bateria.

### Publicar na Play Store
O release é assinado com a chave de upload `D:\Desenvolvimento\CioApps\chaves\app_lojista.jks`
(senha em `.env` da raiz e em `apps/app_lojista/android/key.properties`, ambos fora do Git).
**Faça backup do `.jks` e da senha**: sem eles não é possível atualizar o app na loja.
O `applicationId` `com.cioapps.cardapio` nunca deve mudar.

```bash
cd apps/app_lojista && flutter build appbundle --release --dart-define-from-file=env.json
```

> No MVP o app precisa ficar aberto (uso típico: celular ou tablet fixo no balcão).
> Notificação push com o app fechado fica para a fase 2.

## Fora do MVP (fase 2)

Pix online, retirada no balcão/mesa, cupons, push (FCM), relatórios de vendas, domínio próprio por loja,
assinatura dos lojistas.
