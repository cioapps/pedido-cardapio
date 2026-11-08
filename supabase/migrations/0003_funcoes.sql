-- =====================================================================
-- Cardápio Online - Funções (RPC)
-- =====================================================================

-- ---------------------------------------------------------------------
-- loja_esta_aberta: aberta_manual + (opcional) horários de funcionamento
-- Suporta horário que vira a noite (ex.: 18:00 -> 02:00)
-- ---------------------------------------------------------------------
create or replace function public.loja_esta_aberta(p_id_empresa bigint)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_empresa public.empresas%rowtype;
  v_agora   timestamp;
  v_dia     smallint;
  v_hora    time;
begin
  select * into v_empresa from public.empresas where id = p_id_empresa and ativo = true;
  if not found or not v_empresa.aberta_manual then
    return false;
  end if;
  if not v_empresa.usar_horarios then
    return true;
  end if;

  v_agora := now() at time zone v_empresa.fuso_horario;
  v_dia   := extract(dow from v_agora)::smallint;
  v_hora  := v_agora::time;

  return exists (
    select 1 from public.horarios_funcionamento h
    where h.id_empresa = p_id_empresa
      and (
        -- horário normal no mesmo dia
        (h.dia_semana = v_dia and h.hora_abertura <= h.hora_fechamento
           and v_hora >= h.hora_abertura and v_hora < h.hora_fechamento)
        -- vira a noite: parte de hoje
        or (h.dia_semana = v_dia and h.hora_abertura > h.hora_fechamento
           and v_hora >= h.hora_abertura)
        -- vira a noite: madrugada referente a ontem
        or (h.dia_semana = (v_dia + 6) % 7 and h.hora_abertura > h.hora_fechamento
           and v_hora < h.hora_fechamento)
      )
  );
end;
$$;
grant execute on function public.loja_esta_aberta(bigint) to anon, authenticated;

-- ---------------------------------------------------------------------
-- obter_cardapio: tudo que o cardápio público precisa em uma chamada
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
      'loja_aberta', public.loja_esta_aberta(v_empresa.id)
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
grant execute on function public.obter_cardapio(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- criar_pedido: chamada pelo cardápio público.
-- Recalcula TODOS os valores no servidor e valida as regras.
-- Formato de p_dados:
-- {
--   "slug_empresa": "lanche-exemplo",
--   "nome_cliente": "...", "telefone_cliente": "...",
--   "logradouro": "...", "numero_endereco": "...", "complemento": "...",
--   "ponto_referencia": "...", "id_bairro_entrega": 1,
--   "forma_pagamento": "dinheiro|cartao|pix", "troco_para": 50,
--   "observacao_pedido": "...",
--   "itens": [
--     { "id_produto": 1, "quantidade": 2, "observacao_item": "sem cebola",
--       "opcoes": [ { "id_opcao": 3, "quantidade": 1 } ] }
--   ]
-- }
-- ---------------------------------------------------------------------
create or replace function public.criar_pedido(p_dados jsonb)
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
  -- Empresa
  select * into v_empresa from public.empresas
  where slug_empresa = p_dados->>'slug_empresa' and ativo = true;
  if not found then
    raise exception 'Loja não encontrada' using errcode = 'P0001';
  end if;
  if not public.loja_esta_aberta(v_empresa.id) then
    raise exception 'A loja está fechada no momento' using errcode = 'P0001';
  end if;

  -- Cliente
  v_nome     := nullif(trim(p_dados->>'nome_cliente'), '');
  v_telefone := regexp_replace(coalesce(p_dados->>'telefone_cliente', ''), '\D', '', 'g');
  if v_nome is null or length(v_nome) > 120 then
    raise exception 'Informe seu nome' using errcode = 'P0001';
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
  if v_forma not in ('dinheiro','cartao','pix') then
    raise exception 'Forma de pagamento inválida' using errcode = 'P0001';
  end if;

  if jsonb_typeof(p_dados->'itens') <> 'array' or jsonb_array_length(p_dados->'itens') = 0 then
    raise exception 'O carrinho está vazio' using errcode = 'P0001';
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
    subtotal, taxa_entrega, valor_total, observacao_pedido)
  values (
    v_empresa.id, v_numero, v_id_cliente, v_nome, v_telefone,
    left(trim(p_dados->>'logradouro'), 200), left(trim(p_dados->>'numero_endereco'), 20),
    left(nullif(trim(p_dados->>'complemento'), ''), 120),
    left(nullif(trim(p_dados->>'ponto_referencia'), ''), 200),
    v_bairro.id, v_bairro.nome_bairro, v_forma, null,
    0, v_bairro.taxa_entrega, 0, left(nullif(trim(p_dados->>'observacao_pedido'), ''), 500))
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

    -- Opções escolhidas
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

    -- Valida mínimo/máximo de cada grupo do produto
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

  if v_subtotal < v_empresa.pedido_minimo then
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
    'numero_pedido', v_numero,
    'codigo_acompanhamento', v_codigo,
    'valor_total', v_total);
end;
$$;
revoke all on function public.criar_pedido(jsonb) from public;
grant execute on function public.criar_pedido(jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------
-- consultar_pedido: acompanhamento pelo cliente (link com código)
-- ---------------------------------------------------------------------
create or replace function public.consultar_pedido(p_codigo uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'numero_pedido', p.numero_pedido,
    'status_pedido', p.status_pedido,
    'criado_em', p.criado_em,
    'nome_cliente', p.nome_cliente,
    'nome_bairro', p.nome_bairro,
    'forma_pagamento', p.forma_pagamento,
    'troco_para', p.troco_para,
    'subtotal', p.subtotal,
    'taxa_entrega', p.taxa_entrega,
    'valor_total', p.valor_total,
    'nome_empresa', e.nome_empresa,
    'telefone_whatsapp', e.telefone_whatsapp,
    'cor_principal', e.cor_principal,
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'nome_produto', i.nome_produto,
        'quantidade', i.quantidade,
        'valor_total_item', i.valor_total_item,
        'observacao_item', i.observacao_item,
        'opcoes', coalesce((
          select jsonb_agg(jsonb_build_object(
            'nome_grupo', io.nome_grupo, 'nome_opcao', io.nome_opcao, 'quantidade', io.quantidade)
            order by io.id)
          from public.itens_pedido_opcoes io where io.id_item_pedido = i.id), '[]'::jsonb))
        order by i.id)
      from public.itens_pedido i where i.id_pedido = p.id), '[]'::jsonb))
  from public.pedidos p
  join public.empresas e on e.id = p.id_empresa
  where p.codigo_acompanhamento = p_codigo;
$$;
grant execute on function public.consultar_pedido(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- criar_empresa: cadastro do lojista (usuário logado vira "dono")
-- ---------------------------------------------------------------------
create or replace function public.criar_empresa(
  p_nome_empresa text,
  p_slug_empresa text,
  p_telefone_whatsapp text
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'É preciso estar logado' using errcode = 'P0001';
  end if;
  if nullif(trim(p_nome_empresa), '') is null then
    raise exception 'Informe o nome da loja' using errcode = 'P0001';
  end if;
  if p_slug_empresa !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(p_slug_empresa) > 60 then
    raise exception 'Link inválido: use letras minúsculas, números e hífen' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.empresas where slug_empresa = p_slug_empresa) then
    raise exception 'Esse link já está em uso' using errcode = 'P0001';
  end if;

  insert into public.empresas (nome_empresa, slug_empresa, telefone_whatsapp)
  values (trim(p_nome_empresa), p_slug_empresa,
          regexp_replace(coalesce(p_telefone_whatsapp, ''), '\D', '', 'g'))
  returning id into v_id;

  insert into public.usuarios_empresa (id_empresa, id_usuario_auth, papel)
  values (v_id, v_uid, 'dono');

  return v_id;
end;
$$;
revoke all on function public.criar_empresa(text, text, text) from public, anon;
grant execute on function public.criar_empresa(text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- salvar_grupos_do_produto: substitui os grupos vinculados a um produto
-- (o painel marca/desmarca checkboxes e salva tudo de uma vez)
-- ---------------------------------------------------------------------
create or replace function public.salvar_grupos_do_produto(
  p_id_produto bigint,
  p_ids_grupos bigint[]
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_id_empresa bigint;
begin
  select id_empresa into v_id_empresa from public.produtos where id = p_id_produto;
  if v_id_empresa is null or v_id_empresa not in (select public.empresas_do_usuario()) then
    raise exception 'Produto não encontrado' using errcode = 'P0001';
  end if;

  delete from public.produtos_grupos_opcoes
  where id_produto = p_id_produto
    and not (id_grupo_opcao = any(coalesce(p_ids_grupos, '{}')));

  insert into public.produtos_grupos_opcoes (id_empresa, id_produto, id_grupo_opcao, ordem_exibicao)
  select v_id_empresa, p_id_produto, g.id, x.ord
  from unnest(coalesce(p_ids_grupos, '{}')) with ordinality as x(id_grupo, ord)
  join public.grupos_opcoes g on g.id = x.id_grupo and g.id_empresa = v_id_empresa
  on conflict (id_produto, id_grupo_opcao) do update set ordem_exibicao = excluded.ordem_exibicao;
end;
$$;
revoke all on function public.salvar_grupos_do_produto(bigint, bigint[]) from public, anon;
grant execute on function public.salvar_grupos_do_produto(bigint, bigint[]) to authenticated;
