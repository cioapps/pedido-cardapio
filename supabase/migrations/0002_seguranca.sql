-- =====================================================================
-- Cardápio Online - Segurança (RLS)
-- Público (anon): lê apenas o cardápio ativo.
-- Lojista (authenticated): CRUD só nos dados das suas empresas.
-- Pedidos só são criados pela função criar_pedido (security definer).
-- =====================================================================

-- Empresas às quais o usuário logado pertence
create or replace function public.empresas_do_usuario()
returns setof bigint
language sql
stable
security definer
set search_path = ''
as $$
  select ue.id_empresa
  from public.usuarios_empresa ue
  where ue.id_usuario_auth = (select auth.uid());
$$;
revoke all on function public.empresas_do_usuario() from public, anon;
grant execute on function public.empresas_do_usuario() to authenticated;

-- Liga RLS em todas as tabelas
alter table public.empresas               enable row level security;
alter table public.usuarios_empresa       enable row level security;
alter table public.horarios_funcionamento enable row level security;
alter table public.categorias             enable row level security;
alter table public.produtos               enable row level security;
alter table public.grupos_opcoes          enable row level security;
alter table public.opcoes                 enable row level security;
alter table public.produtos_grupos_opcoes enable row level security;
alter table public.bairros_entrega        enable row level security;
alter table public.clientes               enable row level security;
alter table public.pedidos                enable row level security;
alter table public.itens_pedido           enable row level security;
alter table public.itens_pedido_opcoes    enable row level security;

-- ---------------------------------------------------------------------
-- empresas
-- ---------------------------------------------------------------------
create policy empresas_leitura_publica on public.empresas
  for select to anon, authenticated
  using (ativo = true);

create policy empresas_leitura_lojista on public.empresas
  for select to authenticated
  using (id in (select public.empresas_do_usuario()));

create policy empresas_alteracao_lojista on public.empresas
  for update to authenticated
  using (id in (select public.empresas_do_usuario()))
  with check (id in (select public.empresas_do_usuario()));

-- Lojista não altera contador de pedidos nem status ativo diretamente
revoke update on public.empresas from anon, authenticated;
grant update (
  nome_empresa, telefone_whatsapp, logo_url, cor_principal, endereco_empresa,
  pedido_minimo, tempo_entrega_minutos, aberta_manual, usar_horarios, fuso_horario
) on public.empresas to authenticated;
revoke insert, delete on public.empresas from anon, authenticated;

-- ---------------------------------------------------------------------
-- usuarios_empresa
-- ---------------------------------------------------------------------
create policy usuarios_empresa_leitura on public.usuarios_empresa
  for select to authenticated
  using (id_empresa in (select public.empresas_do_usuario()));
revoke insert, update, delete on public.usuarios_empresa from anon, authenticated;

-- ---------------------------------------------------------------------
-- Tabelas do cardápio: leitura pública (ativo) + CRUD do lojista
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['categorias','produtos','grupos_opcoes','opcoes','bairros_entrega'] loop
    execute format($f$
      create policy %1$s_leitura_publica on public.%1$I
        for select to anon, authenticated
        using (ativo = true and exists (
          select 1 from public.empresas e where e.id = %1$I.id_empresa and e.ativo = true));
      create policy %1$s_lojista on public.%1$I
        for all to authenticated
        using (id_empresa in (select public.empresas_do_usuario()))
        with check (id_empresa in (select public.empresas_do_usuario()));
    $f$, t);
  end loop;

  foreach t in array array['horarios_funcionamento','produtos_grupos_opcoes'] loop
    execute format($f$
      create policy %1$s_leitura_publica on public.%1$I
        for select to anon, authenticated
        using (exists (
          select 1 from public.empresas e where e.id = %1$I.id_empresa and e.ativo = true));
      create policy %1$s_lojista on public.%1$I
        for all to authenticated
        using (id_empresa in (select public.empresas_do_usuario()))
        with check (id_empresa in (select public.empresas_do_usuario()));
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- clientes / pedidos / itens: só o lojista lê; ninguém insere direto
-- ---------------------------------------------------------------------
create policy clientes_lojista on public.clientes
  for select to authenticated
  using (id_empresa in (select public.empresas_do_usuario()));

create policy pedidos_leitura_lojista on public.pedidos
  for select to authenticated
  using (id_empresa in (select public.empresas_do_usuario()));

create policy pedidos_alteracao_lojista on public.pedidos
  for update to authenticated
  using (id_empresa in (select public.empresas_do_usuario()))
  with check (id_empresa in (select public.empresas_do_usuario()));

create policy itens_pedido_lojista on public.itens_pedido
  for select to authenticated
  using (id_empresa in (select public.empresas_do_usuario()));

create policy itens_pedido_opcoes_lojista on public.itens_pedido_opcoes
  for select to authenticated
  using (id_empresa in (select public.empresas_do_usuario()));

revoke all on public.clientes, public.pedidos, public.itens_pedido, public.itens_pedido_opcoes from anon;
revoke insert, update, delete on public.clientes, public.itens_pedido, public.itens_pedido_opcoes from authenticated;
revoke insert, update, delete on public.pedidos from authenticated;
grant update (status_pedido, impresso) on public.pedidos to authenticated;

-- ---------------------------------------------------------------------
-- Storage: bucket público "imagens", pasta = id_empresa
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('imagens', 'imagens', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy imagens_envio_lojista on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'imagens'
    and (storage.foldername(name))[1] in (select id_empresa::text from public.usuarios_empresa
                                          where id_usuario_auth = (select auth.uid())));

create policy imagens_alteracao_lojista on storage.objects
  for update to authenticated
  using (
    bucket_id = 'imagens'
    and (storage.foldername(name))[1] in (select id_empresa::text from public.usuarios_empresa
                                          where id_usuario_auth = (select auth.uid())));

create policy imagens_exclusao_lojista on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'imagens'
    and (storage.foldername(name))[1] in (select id_empresa::text from public.usuarios_empresa
                                          where id_usuario_auth = (select auth.uid())));
