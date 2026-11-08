-- =====================================================================
-- 0006 - Notificação push (Firebase) e resumo de vendas
--   * dispositivos_lojista: celulares (token FCM) que recebem aviso da loja
--   * pedido novo (cardápio) ou rascunho do WhatsApp "pronto" dispara a
--     Edge Function notificar-pedido via pg_net (se a extensão existir)
--   * resumo_vendas(inicio, fim): números para a aba Vendas do app
-- =====================================================================

-- pg_net: chamadas HTTP a partir do banco (existe no Supabase; nos testes locais não)
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Configurações internas (URL das funções e segredo do gatilho).
-- Os valores são gravados fora do Git, direto no banco:
--   insert into privado.configuracoes values ('url_funcoes', 'https://<ref>.supabase.co/functions/v1'),
--                                            ('segredo_push', '<segredo>');
-- ---------------------------------------------------------------------
create table if not exists privado.configuracoes (
  chave text primary key,
  valor text not null
);
revoke all on privado.configuracoes from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Dispositivos do lojista
-- ---------------------------------------------------------------------
create table public.dispositivos_lojista (
  id               bigint generated always as identity primary key,
  id_empresa       bigint not null references public.empresas(id) on delete cascade,
  id_usuario_auth  uuid not null references auth.users(id) on delete cascade,
  token_fcm        text not null unique,
  plataforma       text not null default 'android',
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index on public.dispositivos_lojista (id_empresa);
create trigger dispositivos_lojista_atualizado_em
  before update on public.dispositivos_lojista
  for each row execute function public.definir_atualizado_em();
alter table public.dispositivos_lojista enable row level security;
-- ninguém acessa direto: só pelas funções abaixo e pela Edge Function (service role)
revoke all on public.dispositivos_lojista from anon, authenticated;

-- O app chama ao entrar (e quando o Firebase troca o token)
create or replace function public.registrar_dispositivo(p_token text, p_plataforma text default 'android')
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_empresa bigint;
begin
  if auth.uid() is null then
    raise exception 'Faça login' using errcode = 'P0001';
  end if;
  if coalesce(length(p_token), 0) < 20 then
    raise exception 'Token inválido' using errcode = 'P0001';
  end if;
  select e into v_empresa from public.empresas_do_usuario() e order by e limit 1;
  if v_empresa is null then
    raise exception 'Conta sem loja' using errcode = 'P0001';
  end if;
  insert into public.dispositivos_lojista (id_empresa, id_usuario_auth, token_fcm, plataforma)
  values (v_empresa, auth.uid(), p_token, coalesce(p_plataforma, 'android'))
  on conflict (token_fcm) do update
    set id_empresa = excluded.id_empresa,
        id_usuario_auth = excluded.id_usuario_auth,
        atualizado_em = now();
end;
$$;
revoke all on function public.registrar_dispositivo(text, text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text) to authenticated;

-- O app chama ao sair da conta (para de receber aviso desta loja)
create or replace function public.remover_dispositivo(p_token text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  delete from public.dispositivos_lojista where token_fcm = p_token and id_usuario_auth = auth.uid();
$$;
revoke all on function public.remover_dispositivo(text) from public, anon;
grant execute on function public.remover_dispositivo(text) to authenticated;

-- ---------------------------------------------------------------------
-- Gatilho: chama a Edge Function notificar-pedido (sem travar o pedido)
-- ---------------------------------------------------------------------
create or replace function privado.enviar_aviso(p_id_empresa bigint, p_tipo text, p_titulo text, p_texto text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_segredo text;
begin
  -- sem pg_net (ex.: testes locais) ou sem configuração: não avisa, mas não falha
  if to_regproc('net.http_post') is null then
    return;
  end if;
  select valor into v_url from privado.configuracoes where chave = 'url_funcoes';
  select valor into v_segredo from privado.configuracoes where chave = 'segredo_push';
  if v_url is null or v_segredo is null then
    return;
  end if;
  if not exists (select 1 from public.dispositivos_lojista where id_empresa = p_id_empresa) then
    return;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 5000)'
    using v_url || '/notificar-pedido',
          jsonb_build_object('id_empresa', p_id_empresa, 'tipo', p_tipo, 'titulo', p_titulo, 'texto', p_texto),
          jsonb_build_object('Content-Type', 'application/json', 'x-segredo', v_segredo);
exception when others then
  -- aviso é "melhor esforço": nunca impede o pedido de entrar
  raise warning 'falha ao enviar aviso push: %', sqlerrm;
end;
$$;
revoke all on function privado.enviar_aviso(bigint, text, text, text) from public, anon, authenticated;

create or replace function privado.moeda(p_valor numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'R$ ' || replace(to_char(coalesce(p_valor, 0), 'FM999999990.00'), '.', ',');
$$;

-- Roda no fim da transação (deferred): o total do pedido só é calculado depois dos itens
create or replace function privado.avisar_pedido_novo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.pedidos%rowtype;
begin
  select * into v from public.pedidos where id = new.id;
  if found and v.status_pedido = 'novo' then
    perform privado.enviar_aviso(
      v.id_empresa, 'pedido',
      'Novo pedido #' || v.numero_pedido,
      v.nome_cliente || ' · ' || privado.moeda(v.valor_total) || ' · ' || v.nome_bairro);
  end if;
  return null;
end;
$$;
revoke all on function privado.avisar_pedido_novo() from public, anon, authenticated;

create constraint trigger pedidos_avisar_novo
  after insert on public.pedidos
  deferrable initially deferred
  for each row execute function privado.avisar_pedido_novo();

create or replace function privado.avisar_rascunho_pronto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
begin
  if new.status_rascunho = 'pronto' and (tg_op = 'INSERT' or old.status_rascunho is distinct from 'pronto') then
    select coalesce(nullif(new.dados_pedido->>'nome_cliente', ''), c.nome_contato, 'Cliente')
      into v_nome
      from public.conversas_whatsapp c where c.id = new.id_conversa;
    perform privado.enviar_aviso(
      new.id_empresa, 'rascunho',
      'Pedido do WhatsApp pronto',
      coalesce(v_nome, 'Cliente') || ' · ' || privado.moeda(new.valor_estimado) || ' · toque para conferir');
  end if;
  return null;
end;
$$;
revoke all on function privado.avisar_rascunho_pronto() from public, anon, authenticated;

create trigger rascunhos_avisar_pronto
  after insert or update of status_rascunho on public.rascunhos_pedido
  for each row execute function privado.avisar_rascunho_pronto();

-- ---------------------------------------------------------------------
-- Resumo de vendas (aba Vendas). Datas no fuso da loja; cancelados fora do total.
-- ---------------------------------------------------------------------
create or replace function public.resumo_vendas(p_inicio date, p_fim date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_empresa public.empresas%rowtype;
  v_de timestamptz;
  v_ate timestamptz;
  v_dias int;
  v_resultado jsonb;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    raise exception 'Período inválido' using errcode = 'P0001';
  end if;
  v_dias := p_fim - p_inicio + 1;
  if v_dias > 400 then
    raise exception 'Período muito longo' using errcode = 'P0001';
  end if;

  select e.* into v_empresa
    from public.empresas e
   where e.id in (select public.empresas_do_usuario())
   order by e.id limit 1;
  if not found then
    raise exception 'Conta sem loja' using errcode = 'P0001';
  end if;

  v_de := p_inicio::timestamp at time zone v_empresa.fuso_horario;
  v_ate := (p_fim + 1)::timestamp at time zone v_empresa.fuso_horario;

  with periodo as (
    select p.* from public.pedidos p
     where p.id_empresa = v_empresa.id and p.criado_em >= v_de and p.criado_em < v_ate
  ),
  validos as (select * from periodo where status_pedido <> 'cancelado'),
  anterior as (
    select coalesce(sum(p.valor_total), 0) total, count(*) qtd
      from public.pedidos p
     where p.id_empresa = v_empresa.id and p.status_pedido <> 'cancelado'
       and p.criado_em >= v_de - (v_dias || ' days')::interval and p.criado_em < v_de
  )
  select jsonb_build_object(
    'inicio', p_inicio,
    'fim', p_fim,
    'faturamento', coalesce((select sum(valor_total) from validos), 0),
    'pedidos', (select count(*) from validos),
    'ticket_medio', coalesce((select round(avg(valor_total), 2) from validos), 0),
    'taxas_entrega', coalesce((select sum(taxa_entrega) from validos), 0),
    'cancelados', (select count(*) from periodo where status_pedido = 'cancelado'),
    'faturamento_anterior', (select total from anterior),
    'pedidos_anterior', (select qtd from anterior),
    'por_dia', (
      select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia, 'pedidos', coalesce(x.qtd, 0), 'faturamento', coalesce(x.total, 0))
                                order by d.dia), '[]'::jsonb)
        from (select generate_series(p_inicio, p_fim, interval '1 day')::date dia) d
        left join (
          select (criado_em at time zone v_empresa.fuso_horario)::date dia, count(*) qtd, sum(valor_total) total
            from validos group by 1
        ) x on x.dia = d.dia
    ),
    'por_hora', (
      select coalesce(jsonb_agg(jsonb_build_object('hora', hora, 'pedidos', qtd) order by hora), '[]'::jsonb)
        from (select extract(hour from criado_em at time zone v_empresa.fuso_horario)::int hora, count(*) qtd
                from validos group by 1) h
    ),
    'mais_vendidos', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', nome, 'quantidade', qtd, 'valor', total)
                                order by qtd desc, total desc), '[]'::jsonb)
        from (select i.nome_produto nome, sum(i.quantidade) qtd, sum(i.valor_total_item) total
                from public.itens_pedido i join validos v on v.id = i.id_pedido
               group by i.nome_produto
               order by 2 desc, 3 desc
               limit 5) t
    ),
    'por_pagamento', (
      select coalesce(jsonb_agg(jsonb_build_object('forma', forma_pagamento, 'pedidos', qtd, 'valor', total)
                                order by total desc), '[]'::jsonb)
        from (select forma_pagamento, count(*) qtd, sum(valor_total) total from validos group by 1) f
    ),
    'por_origem', (
      select coalesce(jsonb_agg(jsonb_build_object('origem', origem_pedido, 'pedidos', qtd, 'valor', total)), '[]'::jsonb)
        from (select origem_pedido, count(*) qtd, sum(valor_total) total from validos group by 1) o
    )
  ) into v_resultado;

  return v_resultado;
end;
$$;
revoke all on function public.resumo_vendas(date, date) from public, anon;
grant execute on function public.resumo_vendas(date, date) to authenticated;
