-- =====================================================================
-- Cardápio Online - Módulos por loja + WhatsApp com IA
--   * modulo_cardapio_ativo / modulo_whatsapp_ativo (só o administrador muda)
--   * conexões, conversas, mensagens e rascunhos de pedido do WhatsApp
--   * criar_pedido refatorado: lógica comum em privado.inserir_pedido
-- =====================================================================

create schema if not exists privado;
revoke all on schema privado from public;

-- ---------------------------------------------------------------------
-- Administradores do sistema (você), separados dos lojistas
-- ---------------------------------------------------------------------
create table public.administradores_sistema (
  id               bigint generated always as identity primary key,
  id_usuario_auth  uuid not null unique references auth.users(id) on delete cascade,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
alter table public.administradores_sistema enable row level security;
revoke all on public.administradores_sistema from anon, authenticated;
create trigger tg_administradores_sistema_atualizado_em before update on public.administradores_sistema
  for each row execute function public.definir_atualizado_em();

create or replace function public.e_administrador()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.administradores_sistema a
    where a.id_usuario_auth = (select auth.uid()));
$$;
revoke all on function public.e_administrador() from public, anon;
grant execute on function public.e_administrador() to authenticated;

-- ---------------------------------------------------------------------
-- Módulos por loja
-- ---------------------------------------------------------------------
alter table public.empresas
  add column modulo_cardapio_ativo boolean not null default true,
  add column modulo_whatsapp_ativo boolean not null default false;
-- (as colunas novas ficam fora do grant update do lojista definido em 0002)

-- links que são rotas do sistema não podem virar loja
alter table public.empresas
  add constraint slug_empresa_nao_reservado
  check (slug_empresa not in ('painel', 'admin', 'assets', 'api', 'login'));

create or replace function public.definir_modulos_empresa(
  p_id_empresa bigint,
  p_modulo_cardapio boolean,
  p_modulo_whatsapp boolean
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.e_administrador() then
    raise exception 'Apenas administradores' using errcode = 'P0001';
  end if;
  update public.empresas
     set modulo_cardapio_ativo = p_modulo_cardapio,
         modulo_whatsapp_ativo = p_modulo_whatsapp
   where id = p_id_empresa;
  if not found then
    raise exception 'Loja não encontrada' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function public.definir_modulos_empresa(bigint, boolean, boolean) from public, anon;
grant execute on function public.definir_modulos_empresa(bigint, boolean, boolean) to authenticated;

create or replace function public.listar_empresas_admin()
returns table (
  id bigint, nome_empresa text, slug_empresa text, telefone_whatsapp text, ativo boolean,
  modulo_cardapio_ativo boolean, modulo_whatsapp_ativo boolean, status_conexao text, criado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.e_administrador() then
    raise exception 'Apenas administradores' using errcode = 'P0001';
  end if;
  return query
    select e.id, e.nome_empresa, e.slug_empresa, e.telefone_whatsapp, e.ativo,
           e.modulo_cardapio_ativo, e.modulo_whatsapp_ativo, c.status_conexao, e.criado_em
    from public.empresas e
    left join public.conexoes_whatsapp c on c.id_empresa = e.id
    order by e.criado_em desc;
end;
$$;
revoke all on function public.listar_empresas_admin() from public, anon;
grant execute on function public.listar_empresas_admin() to authenticated;

-- ---------------------------------------------------------------------
-- conexoes_whatsapp (uma instância uazapiGO por loja)
-- token_instancia e segredo_webhook: só as Edge Functions (service role) leem
-- ---------------------------------------------------------------------
create table public.conexoes_whatsapp (
  id                 bigint generated always as identity primary key,
  id_empresa         bigint not null unique references public.empresas(id) on delete cascade,
  nome_instancia     text not null,
  token_instancia    text not null,
  segredo_webhook    text not null unique
                     default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  status_conexao     text not null default 'disconnected',
  numero_conectado   text,
  ia_ativa           boolean not null default true,
  transcrever_audio  boolean not null default true,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- conversas_whatsapp (um chat por contato)
-- ---------------------------------------------------------------------
create table public.conversas_whatsapp (
  id                  bigint generated always as identity primary key,
  id_empresa          bigint not null references public.empresas(id) on delete cascade,
  chat_id             text not null,
  nome_contato        text,
  telefone_contato    text,
  ultima_mensagem_em  timestamptz,
  ignorar_conversa    boolean not null default false,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  unique (id_empresa, chat_id)
);

-- ---------------------------------------------------------------------
-- mensagens_whatsapp
-- ---------------------------------------------------------------------
create table public.mensagens_whatsapp (
  id                   bigint generated always as identity primary key,
  id_empresa           bigint not null references public.empresas(id) on delete cascade,
  id_conversa          bigint not null references public.conversas_whatsapp(id) on delete cascade,
  id_mensagem_externa  text not null,
  enviada_pela_loja    boolean not null default false,
  tipo_mensagem        text not null default 'texto',
  texto_mensagem       text,
  transcricao_audio    text,
  enviada_em           timestamptz not null default now(),
  criado_em            timestamptz not null default now(),
  atualizado_em        timestamptz not null default now(),
  unique (id_empresa, id_mensagem_externa)
);
create index on public.mensagens_whatsapp (id_conversa, enviada_em);

-- ---------------------------------------------------------------------
-- rascunhos_pedido (o que a IA montou a partir da conversa)
-- dados_pedido usa o MESMO formato do criar_pedido
-- ---------------------------------------------------------------------
create table public.rascunhos_pedido (
  id                             bigint generated always as identity primary key,
  id_empresa                     bigint not null references public.empresas(id) on delete cascade,
  id_conversa                    bigint not null references public.conversas_whatsapp(id) on delete cascade,
  status_rascunho                text not null default 'montando'
                                 check (status_rascunho in ('montando','pronto','confirmado','descartado')),
  dados_pedido                   jsonb not null default '{}'::jsonb,
  pendencias                     jsonb not null default '[]'::jsonb,
  resumo_ia                      text,
  valor_estimado                 numeric(10,2) not null default 0,
  id_ultima_mensagem_analisada   bigint references public.mensagens_whatsapp(id) on delete set null,
  id_pedido                      bigint references public.pedidos(id) on delete set null,
  criado_em                      timestamptz not null default now(),
  atualizado_em                  timestamptz not null default now()
);
create index on public.rascunhos_pedido (id_empresa, status_rascunho);
create index on public.rascunhos_pedido (id_conversa);
create index on public.rascunhos_pedido (id_pedido);
create index on public.rascunhos_pedido (id_ultima_mensagem_analisada);
-- no máximo um rascunho aberto por conversa
create unique index rascunho_aberto_por_conversa on public.rascunhos_pedido (id_conversa)
  where status_rascunho in ('montando','pronto');

-- Origem do pedido
alter table public.pedidos
  add column origem_pedido text not null default 'cardapio' check (origem_pedido in ('cardapio','whatsapp')),
  add column id_conversa_whatsapp bigint references public.conversas_whatsapp(id) on delete set null;
create index on public.pedidos (id_conversa_whatsapp);

-- Triggers atualizado_em
do $$
declare t text;
begin
  foreach t in array array['conexoes_whatsapp','conversas_whatsapp','mensagens_whatsapp','rascunhos_pedido'] loop
    execute format(
      'create trigger tg_%1$s_atualizado_em before update on public.%1$I
       for each row execute function public.definir_atualizado_em()', t);
  end loop;
end $$;

alter publication supabase_realtime add table public.rascunhos_pedido;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.conexoes_whatsapp  enable row level security;
alter table public.conversas_whatsapp enable row level security;
alter table public.mensagens_whatsapp enable row level security;
alter table public.rascunhos_pedido   enable row level security;

revoke all on public.conexoes_whatsapp, public.conversas_whatsapp,
              public.mensagens_whatsapp, public.rascunhos_pedido from anon;
revoke all on public.conexoes_whatsapp, public.conversas_whatsapp,
              public.mensagens_whatsapp, public.rascunhos_pedido from authenticated;

-- conexão: lojista lê o status (sem token/segredo) e liga/desliga IA e áudio
grant select (id, id_empresa, nome_instancia, status_conexao, numero_conectado, ia_ativa,
              transcrever_audio, criado_em, atualizado_em) on public.conexoes_whatsapp to authenticated;
grant update (ia_ativa, transcrever_audio) on public.conexoes_whatsapp to authenticated;
create policy conexoes_whatsapp_lojista_leitura on public.conexoes_whatsapp
  for select to authenticated using (id_empresa in (select public.empresas_do_usuario()));
create policy conexoes_whatsapp_lojista_alteracao on public.conexoes_whatsapp
  for update to authenticated
  using (id_empresa in (select public.empresas_do_usuario()))
  with check (id_empresa in (select public.empresas_do_usuario()));

-- conversas: lê e marca "ignorar"
grant select on public.conversas_whatsapp to authenticated;
grant update (ignorar_conversa) on public.conversas_whatsapp to authenticated;
create policy conversas_whatsapp_lojista_leitura on public.conversas_whatsapp
  for select to authenticated using (id_empresa in (select public.empresas_do_usuario()));
create policy conversas_whatsapp_lojista_alteracao on public.conversas_whatsapp
  for update to authenticated
  using (id_empresa in (select public.empresas_do_usuario()))
  with check (id_empresa in (select public.empresas_do_usuario()));

-- mensagens: só leitura
grant select on public.mensagens_whatsapp to authenticated;
create policy mensagens_whatsapp_lojista_leitura on public.mensagens_whatsapp
  for select to authenticated using (id_empresa in (select public.empresas_do_usuario()));

-- rascunhos: lê e descarta (confirmar é pela função confirmar_rascunho)
grant select on public.rascunhos_pedido to authenticated;
grant update (status_rascunho) on public.rascunhos_pedido to authenticated;
create policy rascunhos_pedido_lojista_leitura on public.rascunhos_pedido
  for select to authenticated using (id_empresa in (select public.empresas_do_usuario()));
create policy rascunhos_pedido_lojista_descarte on public.rascunhos_pedido
  for update to authenticated
  using (id_empresa in (select public.empresas_do_usuario()) and status_rascunho in ('montando','pronto'))
  with check (id_empresa in (select public.empresas_do_usuario()) and status_rascunho = 'descartado');

-- =====================================================================
-- Pedido: lógica comum (cardápio e WhatsApp)
-- =====================================================================
create or replace function privado.inserir_pedido(
  p_id_empresa bigint,
  p_dados jsonb,
  p_origem text,
  p_checar_aberta boolean,
  p_status_inicial text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa       public.empresas%rowtype;
  v_bairro        public.bairros_entrega%rowtype;
  v_produto       public.produtos%rowtype;
  v_opcao         record;
  v_grupo         record;
  v_item          jsonb;
  v_opc           jsonb;
  v_qtd           integer;
  v_qtd_opc       integer;
  v_preco_unit    numeric(10,2);
  v_subtotal      numeric(10,2) := 0;
  v_total         numeric(10,2);
  v_troco         numeric(10,2);
  v_numero        integer;
  v_id_cliente    bigint;
  v_id_pedido     bigint;
  v_id_item       bigint;
  v_codigo        uuid;
  v_telefone      text;
  v_nome          text;
  v_forma         text;
  v_soma_grupo    integer;
begin
  select * into v_empresa from public.empresas where id = p_id_empresa and ativo = true;
  if not found then
    raise exception 'Loja não encontrada' using errcode = 'P0001';
  end if;
  if p_checar_aberta and not public.loja_esta_aberta(v_empresa.id) then
    raise exception 'A loja está fechada no momento' using errcode = 'P0001';
  end if;

  -- Cliente
  v_nome     := nullif(trim(p_dados->>'nome_cliente'), '');
  v_telefone := regexp_replace(coalesce(p_dados->>'telefone_cliente', ''), '\D', '', 'g');
  if v_nome is null or length(v_nome) > 120 then
    raise exception 'Informe o nome do cliente' using errcode = 'P0001';
  end if;
  if length(v_telefone) < 10 or length(v_telefone) > 13 then
    raise exception 'Telefone inválido' using errcode = 'P0001';
  end if;
  if nullif(trim(p_dados->>'logradouro'), '') is null
     or nullif(trim(p_dados->>'numero_endereco'), '') is null then
    raise exception 'Informe o endereço de entrega' using errcode = 'P0001';
  end if;

  -- Bairro
  select * into v_bairro from public.bairros_entrega
  where id = (p_dados->>'id_bairro_entrega')::bigint
    and id_empresa = v_empresa.id and ativo = true;
  if not found then
    raise exception 'Bairro não atendido' using errcode = 'P0001';
  end if;

  -- Pagamento
  v_forma := p_dados->>'forma_pagamento';
  if v_forma is null or v_forma not in ('dinheiro','cartao','pix') then
    raise exception 'Forma de pagamento inválida' using errcode = 'P0001';
  end if;

  if jsonb_typeof(p_dados->'itens') is distinct from 'array' or jsonb_array_length(p_dados->'itens') = 0 then
    raise exception 'O pedido está sem itens' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_dados->'itens') > 50 then
    raise exception 'Pedido com itens demais' using errcode = 'P0001';
  end if;

  -- Número sequencial por loja (trava a linha da empresa)
  update public.empresas
     set ultimo_numero_pedido = ultimo_numero_pedido + 1
   where id = v_empresa.id
  returning ultimo_numero_pedido into v_numero;

  -- Cliente (upsert pelo telefone)
  insert into public.clientes (id_empresa, nome_cliente, telefone_cliente, ultimo_endereco)
  values (v_empresa.id, v_nome, v_telefone, jsonb_build_object(
    'logradouro', p_dados->>'logradouro',
    'numero_endereco', p_dados->>'numero_endereco',
    'complemento', p_dados->>'complemento',
    'ponto_referencia', p_dados->>'ponto_referencia',
    'id_bairro_entrega', v_bairro.id))
  on conflict (id_empresa, telefone_cliente) do update
    set nome_cliente = excluded.nome_cliente,
        ultimo_endereco = excluded.ultimo_endereco
  returning id into v_id_cliente;

  -- Pedido (valores provisórios, atualizados no final)
  insert into public.pedidos (
    id_empresa, numero_pedido, id_cliente, nome_cliente, telefone_cliente,
    logradouro, numero_endereco, complemento, ponto_referencia,
    id_bairro_entrega, nome_bairro, forma_pagamento, troco_para,
    subtotal, taxa_entrega, valor_total, observacao_pedido, status_pedido, origem_pedido)
  values (
    v_empresa.id, v_numero, v_id_cliente, v_nome, v_telefone,
    left(trim(p_dados->>'logradouro'), 200), left(trim(p_dados->>'numero_endereco'), 20),
    left(nullif(trim(p_dados->>'complemento'), ''), 120),
    left(nullif(trim(p_dados->>'ponto_referencia'), ''), 200),
    v_bairro.id, v_bairro.nome_bairro, v_forma, null,
    0, v_bairro.taxa_entrega, 0, left(nullif(trim(p_dados->>'observacao_pedido'), ''), 500),
    p_status_inicial, p_origem)
  returning id, codigo_acompanhamento into v_id_pedido, v_codigo;

  -- Itens
  for v_item in select * from jsonb_array_elements(p_dados->'itens') loop
    v_qtd := coalesce((v_item->>'quantidade')::integer, 0);
    if v_qtd < 1 or v_qtd > 99 then
      raise exception 'Quantidade inválida' using errcode = 'P0001';
    end if;

    select * into v_produto from public.produtos
    where id = (v_item->>'id_produto')::bigint and id_empresa = v_empresa.id and ativo = true;
    if not found then
      raise exception 'Um dos produtos não está mais disponível' using errcode = 'P0001';
    end if;

    insert into public.itens_pedido (
      id_empresa, id_pedido, id_produto, nome_produto, quantidade,
      preco_unitario, valor_total_item, observacao_item)
    values (
      v_empresa.id, v_id_pedido, v_produto.id, v_produto.nome_produto, v_qtd,
      0, 0, left(nullif(trim(v_item->>'observacao_item'), ''), 300))
    returning id into v_id_item;

    v_preco_unit := v_produto.preco_produto;

    for v_opc in select * from jsonb_array_elements(coalesce(v_item->'opcoes', '[]'::jsonb)) loop
      v_qtd_opc := coalesce((v_opc->>'quantidade')::integer, 1);
      if v_qtd_opc < 1 or v_qtd_opc > 20 then
        raise exception 'Quantidade de opção inválida' using errcode = 'P0001';
      end if;

      select o.id, o.nome_opcao, o.preco_adicional, g.nome_grupo
        into v_opcao
      from public.opcoes o
      join public.grupos_opcoes g on g.id = o.id_grupo_opcao and g.ativo
      join public.produtos_grupos_opcoes pg
        on pg.id_grupo_opcao = g.id and pg.id_produto = v_produto.id
      where o.id = (v_opc->>'id_opcao')::bigint and o.ativo;
      if not found then
        raise exception 'Opção indisponível para %', v_produto.nome_produto using errcode = 'P0001';
      end if;

      insert into public.itens_pedido_opcoes (
        id_empresa, id_item_pedido, id_opcao, nome_grupo, nome_opcao, quantidade, preco_adicional)
      values (
        v_empresa.id, v_id_item, v_opcao.id, v_opcao.nome_grupo, v_opcao.nome_opcao,
        v_qtd_opc, v_opcao.preco_adicional);

      v_preco_unit := v_preco_unit + v_opcao.preco_adicional * v_qtd_opc;
    end loop;

    -- mínimo/máximo de cada grupo do produto
    for v_grupo in
      select g.id, g.nome_grupo, g.minimo_selecao, g.maximo_selecao
      from public.produtos_grupos_opcoes pg
      join public.grupos_opcoes g on g.id = pg.id_grupo_opcao and g.ativo
      where pg.id_produto = v_produto.id
    loop
      select coalesce(sum(ipo.quantidade), 0) into v_soma_grupo
      from public.itens_pedido_opcoes ipo
      join public.opcoes o on o.id = ipo.id_opcao
      where ipo.id_item_pedido = v_id_item and o.id_grupo_opcao = v_grupo.id;

      if v_soma_grupo < v_grupo.minimo_selecao then
        raise exception '%: escolha pelo menos % em "%"',
          v_produto.nome_produto, v_grupo.minimo_selecao, v_grupo.nome_grupo using errcode = 'P0001';
      end if;
      if v_soma_grupo > v_grupo.maximo_selecao then
        raise exception '%: escolha no máximo % em "%"',
          v_produto.nome_produto, v_grupo.maximo_selecao, v_grupo.nome_grupo using errcode = 'P0001';
      end if;
    end loop;

    update public.itens_pedido
       set preco_unitario = v_preco_unit,
           valor_total_item = v_preco_unit * v_qtd
     where id = v_id_item;

    v_subtotal := v_subtotal + v_preco_unit * v_qtd;
  end loop;

  -- pedido mínimo vale para o cardápio; no WhatsApp quem decide é o lojista
  if p_origem = 'cardapio' and v_subtotal < v_empresa.pedido_minimo then
    raise exception 'O pedido mínimo é de R$ %', to_char(v_empresa.pedido_minimo, 'FM999G990D00')
      using errcode = 'P0001';
  end if;

  v_total := v_subtotal + v_bairro.taxa_entrega;

  if v_forma = 'dinheiro' and nullif(p_dados->>'troco_para', '') is not null then
    v_troco := (p_dados->>'troco_para')::numeric(10,2);
    if v_troco < v_total then
      raise exception 'O valor para troco deve ser maior que o total do pedido' using errcode = 'P0001';
    end if;
  end if;

  update public.pedidos
     set subtotal = v_subtotal,
         valor_total = v_total,
         troco_para = v_troco
   where id = v_id_pedido;

  return jsonb_build_object(
    'id_pedido', v_id_pedido,
    'numero_pedido', v_numero,
    'codigo_acompanhamento', v_codigo,
    'valor_total', v_total);
end;
$$;
revoke all on function privado.inserir_pedido(bigint, jsonb, text, boolean, text) from public, anon, authenticated;

-- criar_pedido (cardápio público): mesma assinatura, agora respeita o módulo
create or replace function public.criar_pedido(p_dados jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa public.empresas%rowtype;
  v_resultado jsonb;
begin
  select * into v_empresa from public.empresas
  where slug_empresa = p_dados->>'slug_empresa' and ativo = true;
  if not found then
    raise exception 'Loja não encontrada' using errcode = 'P0001';
  end if;
  if not v_empresa.modulo_cardapio_ativo then
    raise exception 'Esta loja recebe pedidos apenas pelo WhatsApp' using errcode = 'P0001';
  end if;

  v_resultado := privado.inserir_pedido(v_empresa.id, p_dados, 'cardapio', true, 'novo');
  -- o cliente não precisa do id interno
  return v_resultado - 'id_pedido';
end;
$$;

-- obter_cardapio: informa se o módulo de cardápio está ligado
create or replace function public.obter_cardapio(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_empresa public.empresas%rowtype;
begin
  select * into v_empresa from public.empresas where slug_empresa = p_slug and ativo = true;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'empresa', jsonb_build_object(
      'id', v_empresa.id,
      'nome_empresa', v_empresa.nome_empresa,
      'slug_empresa', v_empresa.slug_empresa,
      'telefone_whatsapp', v_empresa.telefone_whatsapp,
      'logo_url', v_empresa.logo_url,
      'cor_principal', v_empresa.cor_principal,
      'endereco_empresa', v_empresa.endereco_empresa,
      'pedido_minimo', v_empresa.pedido_minimo,
      'tempo_entrega_minutos', v_empresa.tempo_entrega_minutos,
      'loja_aberta', public.loja_esta_aberta(v_empresa.id),
      'cardapio_ativo', v_empresa.modulo_cardapio_ativo
    ),
    'horarios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'dia_semana', h.dia_semana,
        'hora_abertura', to_char(h.hora_abertura, 'HH24:MI'),
        'hora_fechamento', to_char(h.hora_fechamento, 'HH24:MI'))
        order by h.dia_semana, h.hora_abertura)
      from public.horarios_funcionamento h
      where h.id_empresa = v_empresa.id and v_empresa.usar_horarios), '[]'::jsonb),
    'bairros', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'nome_bairro', b.nome_bairro, 'taxa_entrega', b.taxa_entrega)
        order by b.nome_bairro)
      from public.bairros_entrega b
      where b.id_empresa = v_empresa.id and b.ativo), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'nome_categoria', c.nome_categoria,
        'produtos', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', p.id,
            'nome_produto', p.nome_produto,
            'descricao_produto', p.descricao_produto,
            'preco_produto', p.preco_produto,
            'foto_url', p.foto_url,
            'grupos', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', g.id,
                'nome_grupo', g.nome_grupo,
                'minimo_selecao', g.minimo_selecao,
                'maximo_selecao', g.maximo_selecao,
                'opcoes', coalesce((
                  select jsonb_agg(jsonb_build_object(
                    'id', o.id,
                    'nome_opcao', o.nome_opcao,
                    'preco_adicional', o.preco_adicional)
                    order by o.ordem_exibicao, o.id)
                  from public.opcoes o
                  where o.id_grupo_opcao = g.id and o.ativo), '[]'::jsonb))
                order by pg.ordem_exibicao, g.ordem_exibicao, g.id)
              from public.produtos_grupos_opcoes pg
              join public.grupos_opcoes g on g.id = pg.id_grupo_opcao and g.ativo
              where pg.id_produto = p.id), '[]'::jsonb))
            order by p.ordem_exibicao, p.id)
          from public.produtos p
          where p.id_categoria = c.id and p.ativo), '[]'::jsonb))
        order by c.ordem_exibicao, c.id)
      from public.categorias c
      where c.id_empresa = v_empresa.id and c.ativo
        and exists (select 1 from public.produtos p2 where p2.id_categoria = c.id and p2.ativo)
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- confirmar_rascunho: lojista revisou o que a IA montou e confirma
-- p_dados no formato do criar_pedido (pode vir ajustado pelo lojista)
-- ---------------------------------------------------------------------
create or replace function public.confirmar_rascunho(p_id_rascunho bigint, p_dados jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rascunho  public.rascunhos_pedido%rowtype;
  v_conversa  public.conversas_whatsapp%rowtype;
  v_dados     jsonb := p_dados;
  v_resultado jsonb;
begin
  select * into v_rascunho from public.rascunhos_pedido
  where id = p_id_rascunho
    and id_empresa in (select public.empresas_do_usuario())
  for update;
  if not found then
    raise exception 'Rascunho não encontrado' using errcode = 'P0001';
  end if;
  if v_rascunho.status_rascunho not in ('montando','pronto') then
    raise exception 'Este rascunho já foi %', v_rascunho.status_rascunho using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.empresas
                 where id = v_rascunho.id_empresa and modulo_whatsapp_ativo) then
    raise exception 'Módulo WhatsApp desativado para esta loja' using errcode = 'P0001';
  end if;

  -- sem telefone no formulário, usa o número da conversa
  select * into v_conversa from public.conversas_whatsapp where id = v_rascunho.id_conversa;
  if nullif(regexp_replace(coalesce(v_dados->>'telefone_cliente', ''), '\D', '', 'g'), '') is null then
    v_dados := v_dados || jsonb_build_object('telefone_cliente', v_conversa.telefone_contato);
  end if;

  v_resultado := privado.inserir_pedido(v_rascunho.id_empresa, v_dados, 'whatsapp', false, 'aceito');

  update public.pedidos
     set id_conversa_whatsapp = v_rascunho.id_conversa
   where id = (v_resultado->>'id_pedido')::bigint;

  update public.rascunhos_pedido
     set status_rascunho = 'confirmado',
         dados_pedido = v_dados,
         id_pedido = (v_resultado->>'id_pedido')::bigint
   where id = v_rascunho.id;

  return v_resultado;
end;
$$;
revoke all on function public.confirmar_rascunho(bigint, jsonb) from public, anon;
grant execute on function public.confirmar_rascunho(bigint, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- Limpeza: mensagens com mais de 30 dias (agenda no pg_cron se existir)
-- ---------------------------------------------------------------------
create or replace function privado.limpar_mensagens_antigas()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.mensagens_whatsapp where enviada_em < now() - interval '30 days';
$$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('limpar-mensagens-whatsapp', '15 4 * * *',
                          'select privado.limpar_mensagens_antigas()');
  end if;
end $$;
