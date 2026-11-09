-- =====================================================================
-- 0008 - Acompanhamento de uso no painel do administrador
--   * uso_empresas_admin(): números de pedidos por loja (hoje, 7 e 30 dias)
--   * pedidos_recentes_admin(): feed dos últimos pedidos de todas as lojas
--   Só leitura e só para administradores. Não expõe telefone nem endereço
--   do cliente da loja: só o primeiro nome e o bairro.
-- =====================================================================

create or replace function public.uso_empresas_admin()
returns table (
  id_empresa bigint,
  pedidos_hoje integer,
  pedidos_7d integer,
  pedidos_30d integer,
  faturamento_30d numeric,
  pedidos_cardapio_30d integer,
  pedidos_whatsapp_30d integer,
  cancelados_30d integer,
  ultimo_pedido_em timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hoje timestamptz := date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
begin
  if not public.e_administrador() then
    raise exception 'Apenas administradores' using errcode = 'P0001';
  end if;
  return query
    select e.id,
           count(*) filter (where p.criado_em >= v_hoje and p.status_pedido <> 'cancelado')::int,
           count(*) filter (where p.criado_em >= v_hoje - interval '6 days' and p.status_pedido <> 'cancelado')::int,
           count(*) filter (where p.criado_em >= v_hoje - interval '29 days' and p.status_pedido <> 'cancelado')::int,
           coalesce(sum(p.valor_total) filter (where p.criado_em >= v_hoje - interval '29 days' and p.status_pedido <> 'cancelado'), 0),
           count(*) filter (where p.criado_em >= v_hoje - interval '29 days' and p.status_pedido <> 'cancelado' and p.origem_pedido = 'cardapio')::int,
           count(*) filter (where p.criado_em >= v_hoje - interval '29 days' and p.status_pedido <> 'cancelado' and p.origem_pedido = 'whatsapp')::int,
           count(*) filter (where p.criado_em >= v_hoje - interval '29 days' and p.status_pedido = 'cancelado')::int,
           max(p.criado_em)
    from public.empresas e
    left join public.pedidos p on p.id_empresa = e.id
    group by e.id;
end;
$$;
revoke all on function public.uso_empresas_admin() from public, anon;
grant execute on function public.uso_empresas_admin() to authenticated;

create or replace function public.pedidos_recentes_admin(p_limite integer default 50, p_id_empresa bigint default null)
returns table (
  id bigint,
  id_empresa bigint,
  nome_empresa text,
  numero_pedido integer,
  primeiro_nome text,
  nome_bairro text,
  valor_total numeric,
  forma_pagamento text,
  status_pedido text,
  origem_pedido text,
  qtd_itens integer,
  criado_em timestamptz
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
    select p.id, p.id_empresa, e.nome_empresa, p.numero_pedido,
           split_part(trim(p.nome_cliente), ' ', 1),
           p.nome_bairro, p.valor_total, p.forma_pagamento, p.status_pedido, p.origem_pedido,
           (select coalesce(sum(i.quantidade), 0)::int from public.itens_pedido i where i.id_pedido = p.id),
           p.criado_em
    from public.pedidos p
    join public.empresas e on e.id = p.id_empresa
    where p_id_empresa is null or p.id_empresa = p_id_empresa
    order by p.criado_em desc
    limit least(greatest(coalesce(p_limite, 50), 1), 200);
end;
$$;
revoke all on function public.pedidos_recentes_admin(integer, bigint) from public, anon;
grant execute on function public.pedidos_recentes_admin(integer, bigint) to authenticated;
