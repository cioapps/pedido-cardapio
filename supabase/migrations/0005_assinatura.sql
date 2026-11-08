-- =====================================================================
-- 0005 - Assinatura das lojas (bloqueio básico)
--   * situacao_assinatura: 'teste' | 'ativa' | 'bloqueada'
--   * assinatura_valida_ate: até quando está liberada (null = sem prazo)
--   * Loja nova ganha 7 dias de teste. Só o administrador altera.
--   * Loja não liberada: não recebe pedidos (trigger em pedidos), o cardápio
--     mostra "indisponível", o app mostra a tela de bloqueio e a IA para.
-- =====================================================================

alter table public.empresas
  add column situacao_assinatura text not null default 'teste'
    check (situacao_assinatura in ('teste', 'ativa', 'bloqueada')),
  add column assinatura_valida_ate timestamptz default (now() + interval '7 days');

-- Lojas que já existiam continuam liberadas, sem prazo
update public.empresas set situacao_assinatura = 'ativa', assinatura_valida_ate = null;

-- Lojista não altera as colunas novas: o grant de update de 0002 é por coluna e não as inclui.

-- ---------------------------------------------------------------------
-- Regra única de "loja liberada"
-- ---------------------------------------------------------------------
create or replace function public.assinatura_liberada(p_id_empresa bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select e.situacao_assinatura <> 'bloqueada'
           and (e.assinatura_valida_ate is null or e.assinatura_valida_ate > now())
    from public.empresas e
    where e.id = p_id_empresa), false);
$$;
revoke all on function public.assinatura_liberada(bigint) from public;
grant execute on function public.assinatura_liberada(bigint) to anon, authenticated;

-- Situação da loja do usuário logado (o app usa para mostrar o bloqueio).
-- Usa o relógio do servidor, não o do celular.
create or replace function public.minha_assinatura()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'liberada', public.assinatura_liberada(e.id),
    'situacao', e.situacao_assinatura,
    'valida_ate', e.assinatura_valida_ate,
    'dias_restantes', case when e.assinatura_valida_ate is null then null
                           else greatest(0, ceil(extract(epoch from (e.assinatura_valida_ate - now())) / 86400))::int end
  )
  from public.empresas e
  where e.id in (select public.empresas_do_usuario())
  order by e.id
  limit 1;
$$;
revoke all on function public.minha_assinatura() from public, anon;
grant execute on function public.minha_assinatura() to authenticated;

-- ---------------------------------------------------------------------
-- Nenhum pedido entra em loja bloqueada (cardápio ou WhatsApp)
-- ---------------------------------------------------------------------
create or replace function privado.checar_assinatura_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.assinatura_liberada(new.id_empresa) then
    raise exception 'Esta loja está temporariamente indisponível' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function privado.checar_assinatura_pedido() from public, anon, authenticated;

create trigger pedidos_checar_assinatura
  before insert on public.pedidos
  for each row execute function privado.checar_assinatura_pedido();

-- ---------------------------------------------------------------------
-- Administrador: definir a assinatura
-- ---------------------------------------------------------------------
create or replace function public.definir_assinatura_empresa(
  p_id_empresa bigint,
  p_situacao text,
  p_valida_ate timestamptz
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
  if p_situacao not in ('teste', 'ativa', 'bloqueada') then
    raise exception 'Situação inválida' using errcode = 'P0001';
  end if;
  update public.empresas
     set situacao_assinatura = p_situacao,
         assinatura_valida_ate = p_valida_ate
   where id = p_id_empresa;
  if not found then
    raise exception 'Loja não encontrada' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function public.definir_assinatura_empresa(bigint, text, timestamptz) from public, anon;
grant execute on function public.definir_assinatura_empresa(bigint, text, timestamptz) to authenticated;

-- Lista do admin passa a trazer a assinatura (muda o retorno: recria)
drop function public.listar_empresas_admin();
create function public.listar_empresas_admin()
returns table (
  id bigint, nome_empresa text, slug_empresa text, telefone_whatsapp text, ativo boolean,
  modulo_cardapio_ativo boolean, modulo_whatsapp_ativo boolean, status_conexao text, criado_em timestamptz,
  situacao_assinatura text, assinatura_valida_ate timestamptz, assinatura_liberada boolean, email_dono text
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
           e.modulo_cardapio_ativo, e.modulo_whatsapp_ativo, c.status_conexao, e.criado_em,
           e.situacao_assinatura, e.assinatura_valida_ate, public.assinatura_liberada(e.id),
           (select u.email::text from public.usuarios_empresa ue join auth.users u on u.id = ue.id_usuario_auth
             where ue.id_empresa = e.id and ue.papel = 'dono' order by ue.id limit 1)
    from public.empresas e
    left join public.conexoes_whatsapp c on c.id_empresa = e.id
    order by e.criado_em desc;
end;
$$;
revoke all on function public.listar_empresas_admin() from public, anon;
grant execute on function public.listar_empresas_admin() to authenticated;

-- ---------------------------------------------------------------------
-- obter_cardapio: informa se a loja está disponível (assinatura)
-- ---------------------------------------------------------------------
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
      'cardapio_ativo', v_empresa.modulo_cardapio_ativo,
      'loja_disponivel', public.assinatura_liberada(v_empresa.id)
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
