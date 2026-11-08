-- =====================================================================
-- Cardápio Online - Estrutura (multiempresa)
-- Colunas em português, snake_case, PKs bigint identity
-- =====================================================================

create extension if not exists pgcrypto;

-- Trigger genérico para atualizado_em
create or replace function public.definir_atualizado_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- empresas (lojas)
-- ---------------------------------------------------------------------
create table public.empresas (
  id                     bigint generated always as identity primary key,
  nome_empresa           text not null,
  slug_empresa           text not null unique
                         check (slug_empresa ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  telefone_whatsapp      text,
  logo_url               text,
  cor_principal          text not null default '#E63946',
  endereco_empresa       text,
  pedido_minimo          numeric(10,2) not null default 0,
  tempo_entrega_minutos  integer not null default 45,
  aberta_manual          boolean not null default true,
  usar_horarios          boolean not null default false,
  fuso_horario           text not null default 'America/Sao_Paulo',
  ultimo_numero_pedido   integer not null default 0,
  ativo                  boolean not null default true,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- usuarios_empresa (vínculo do usuário do Supabase Auth com a loja)
-- ---------------------------------------------------------------------
create table public.usuarios_empresa (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  id_usuario_auth  uuid   not null references auth.users(id) on delete cascade,
  nome_usuario     text,
  papel            text not null default 'dono' check (papel in ('dono','funcionario')),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (id_empresa, id_usuario_auth)
);
create index on public.usuarios_empresa (id_usuario_auth);

-- ---------------------------------------------------------------------
-- horarios_funcionamento
-- ---------------------------------------------------------------------
create table public.horarios_funcionamento (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  dia_semana       smallint not null check (dia_semana between 0 and 6), -- 0 = domingo
  hora_abertura    time not null,
  hora_fechamento  time not null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index on public.horarios_funcionamento (id_empresa);

-- ---------------------------------------------------------------------
-- categorias
-- ---------------------------------------------------------------------
create table public.categorias (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  nome_categoria   text not null,
  ordem_exibicao   integer not null default 0,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index on public.categorias (id_empresa);

-- ---------------------------------------------------------------------
-- produtos
-- ---------------------------------------------------------------------
create table public.produtos (
  id                 bigint generated always as identity primary key,
  id_empresa         bigint not null references public.empresas(id) on delete cascade,
  id_categoria       bigint not null references public.categorias(id) on delete cascade,
  nome_produto       text not null,
  descricao_produto  text,
  preco_produto      numeric(10,2) not null default 0 check (preco_produto >= 0),
  foto_url           text,
  ordem_exibicao     integer not null default 0,
  ativo              boolean not null default true,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index on public.produtos (id_empresa);
create index on public.produtos (id_categoria);

-- ---------------------------------------------------------------------
-- grupos_opcoes (seleção obrigatória ou adicionais)
--   "Escolha o pão"  -> minimo 1, maximo 1
--   "Adicionais"     -> minimo 0, maximo N
-- ---------------------------------------------------------------------
create table public.grupos_opcoes (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  nome_grupo       text not null,
  minimo_selecao   integer not null default 0 check (minimo_selecao >= 0),
  maximo_selecao   integer not null default 1 check (maximo_selecao >= 1),
  ordem_exibicao   integer not null default 0,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  check (maximo_selecao >= minimo_selecao)
);
create index on public.grupos_opcoes (id_empresa);

-- ---------------------------------------------------------------------
-- opcoes (itens dentro de um grupo)
-- ---------------------------------------------------------------------
create table public.opcoes (
  id                bigint generated always as identity primary key,
  id_empresa        bigint not null references public.empresas(id) on delete cascade,
  id_grupo_opcao    bigint not null references public.grupos_opcoes(id) on delete cascade,
  nome_opcao        text not null,
  preco_adicional   numeric(10,2) not null default 0 check (preco_adicional >= 0),
  ordem_exibicao    integer not null default 0,
  ativo             boolean not null default true,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index on public.opcoes (id_empresa);
create index on public.opcoes (id_grupo_opcao);

-- ---------------------------------------------------------------------
-- produtos_grupos_opcoes (quais grupos aparecem em cada produto)
-- ---------------------------------------------------------------------
create table public.produtos_grupos_opcoes (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  id_produto       bigint not null references public.produtos(id) on delete cascade,
  id_grupo_opcao   bigint not null references public.grupos_opcoes(id) on delete cascade,
  ordem_exibicao   integer not null default 0,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (id_produto, id_grupo_opcao)
);
create index on public.produtos_grupos_opcoes (id_empresa);
create index on public.produtos_grupos_opcoes (id_grupo_opcao);

-- ---------------------------------------------------------------------
-- bairros_entrega (taxa por bairro)
-- ---------------------------------------------------------------------
create table public.bairros_entrega (
  id              bigint generated always as identity primary key,
  id_empresa      bigint not null references public.empresas(id) on delete cascade,
  nome_bairro     text not null,
  taxa_entrega    numeric(10,2) not null default 0 check (taxa_entrega >= 0),
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index on public.bairros_entrega (id_empresa);

-- ---------------------------------------------------------------------
-- clientes (por loja, identificados pelo telefone)
-- ---------------------------------------------------------------------
create table public.clientes (
  id                bigint generated always as identity primary key,
  id_empresa        bigint not null references public.empresas(id) on delete cascade,
  nome_cliente      text not null,
  telefone_cliente  text not null,
  ultimo_endereco   jsonb,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  unique (id_empresa, telefone_cliente)
);

-- ---------------------------------------------------------------------
-- pedidos
-- ---------------------------------------------------------------------
create table public.pedidos (
  id                      bigint generated always as identity primary key,
  id_empresa              bigint not null references public.empresas(id) on delete cascade,
  numero_pedido           integer not null,
  codigo_acompanhamento   uuid not null default gen_random_uuid() unique,
  id_cliente              bigint references public.clientes(id) on delete set null,
  nome_cliente            text not null,
  telefone_cliente        text not null,
  logradouro              text not null,
  numero_endereco         text not null,
  complemento             text,
  ponto_referencia        text,
  id_bairro_entrega       bigint references public.bairros_entrega(id) on delete set null,
  nome_bairro             text not null,
  forma_pagamento         text not null check (forma_pagamento in ('dinheiro','cartao','pix')),
  troco_para              numeric(10,2),
  subtotal                numeric(10,2) not null,
  taxa_entrega            numeric(10,2) not null default 0,
  valor_total             numeric(10,2) not null,
  observacao_pedido       text,
  status_pedido           text not null default 'novo'
                          check (status_pedido in ('novo','aceito','em_preparo','saiu_entrega','entregue','cancelado')),
  impresso                boolean not null default false,
  criado_em               timestamptz not null default now(),
  atualizado_em           timestamptz not null default now(),
  unique (id_empresa, numero_pedido)
);
create index on public.pedidos (id_empresa, criado_em desc);
create index on public.pedidos (id_cliente);
create index on public.pedidos (id_bairro_entrega);

-- ---------------------------------------------------------------------
-- itens_pedido (cópia de nome/preço no momento do pedido)
-- ---------------------------------------------------------------------
create table public.itens_pedido (
  id                 bigint generated always as identity primary key,
  id_empresa         bigint not null references public.empresas(id) on delete cascade,
  id_pedido          bigint not null references public.pedidos(id) on delete cascade,
  id_produto         bigint references public.produtos(id) on delete set null,
  nome_produto       text not null,
  quantidade         integer not null check (quantidade > 0),
  preco_unitario     numeric(10,2) not null,
  valor_total_item   numeric(10,2) not null,
  observacao_item    text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);
create index on public.itens_pedido (id_pedido);
create index on public.itens_pedido (id_empresa);
create index on public.itens_pedido (id_produto);

-- ---------------------------------------------------------------------
-- itens_pedido_opcoes
-- ---------------------------------------------------------------------
create table public.itens_pedido_opcoes (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  id_item_pedido   bigint not null references public.itens_pedido(id) on delete cascade,
  id_opcao         bigint references public.opcoes(id) on delete set null,
  nome_grupo       text not null,
  nome_opcao       text not null,
  quantidade       integer not null default 1 check (quantidade > 0),
  preco_adicional  numeric(10,2) not null default 0,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index on public.itens_pedido_opcoes (id_item_pedido);
create index on public.itens_pedido_opcoes (id_empresa);
create index on public.itens_pedido_opcoes (id_opcao);

-- Triggers atualizado_em
do $$
declare t text;
begin
  foreach t in array array[
    'empresas','usuarios_empresa','horarios_funcionamento','categorias','produtos',
    'grupos_opcoes','opcoes','produtos_grupos_opcoes','bairros_entrega','clientes',
    'pedidos','itens_pedido','itens_pedido_opcoes'
  ] loop
    execute format(
      'create trigger tg_%1$s_atualizado_em before update on public.%1$I
       for each row execute function public.definir_atualizado_em()', t);
  end loop;
end $$;

-- Realtime: app do lojista escuta novos pedidos
alter publication supabase_realtime add table public.pedidos;
