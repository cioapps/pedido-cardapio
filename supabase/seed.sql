-- =====================================================================
-- Loja de exemplo: /lanche-exemplo
-- Para vincular seu usuário a ela (depois de criar a conta no painel):
--   insert into public.usuarios_empresa (id_empresa, id_usuario_auth, papel)
--   select e.id, u.id, 'dono' from public.empresas e, auth.users u
--   where e.slug_empresa = 'lanche-exemplo' and u.email = 'SEU_EMAIL';
-- =====================================================================
do $$
declare
  v_emp bigint;
  v_cat_lanches bigint; v_cat_porcoes bigint; v_cat_bebidas bigint;
  v_g_pao bigint; v_g_ponto bigint; v_g_adic bigint; v_g_molho bigint;
  v_p bigint;
begin
  insert into public.empresas (nome_empresa, slug_empresa, telefone_whatsapp, cor_principal,
    endereco_empresa, pedido_minimo, tempo_entrega_minutos)
  values ('Lanche Exemplo', 'lanche-exemplo', '5511999999999', '#E63946',
    'Rua das Flores, 100 - Centro', 20, 40)
  returning id into v_emp;

  insert into public.categorias (id_empresa, nome_categoria, ordem_exibicao) values (v_emp, 'Lanches', 1) returning id into v_cat_lanches;
  insert into public.categorias (id_empresa, nome_categoria, ordem_exibicao) values (v_emp, 'Porções', 2) returning id into v_cat_porcoes;
  insert into public.categorias (id_empresa, nome_categoria, ordem_exibicao) values (v_emp, 'Bebidas', 3) returning id into v_cat_bebidas;

  -- Grupos reutilizáveis
  insert into public.grupos_opcoes (id_empresa, nome_grupo, minimo_selecao, maximo_selecao, ordem_exibicao)
  values (v_emp, 'Escolha o pão', 1, 1, 1) returning id into v_g_pao;
  insert into public.opcoes (id_empresa, id_grupo_opcao, nome_opcao, preco_adicional, ordem_exibicao) values
    (v_emp, v_g_pao, 'Pão de hambúrguer', 0, 1),
    (v_emp, v_g_pao, 'Pão australiano', 2, 2),
    (v_emp, v_g_pao, 'Pão brioche', 3, 3);

  insert into public.grupos_opcoes (id_empresa, nome_grupo, minimo_selecao, maximo_selecao, ordem_exibicao)
  values (v_emp, 'Ponto da carne', 1, 1, 2) returning id into v_g_ponto;
  insert into public.opcoes (id_empresa, id_grupo_opcao, nome_opcao, preco_adicional, ordem_exibicao) values
    (v_emp, v_g_ponto, 'Mal passada', 0, 1),
    (v_emp, v_g_ponto, 'Ao ponto', 0, 2),
    (v_emp, v_g_ponto, 'Bem passada', 0, 3);

  insert into public.grupos_opcoes (id_empresa, nome_grupo, minimo_selecao, maximo_selecao, ordem_exibicao)
  values (v_emp, 'Adicionais', 0, 10, 3) returning id into v_g_adic;
  insert into public.opcoes (id_empresa, id_grupo_opcao, nome_opcao, preco_adicional, ordem_exibicao) values
    (v_emp, v_g_adic, 'Bacon', 4, 1),
    (v_emp, v_g_adic, 'Cheddar', 3, 2),
    (v_emp, v_g_adic, 'Ovo', 2, 3),
    (v_emp, v_g_adic, 'Hambúrguer extra', 7, 4),
    (v_emp, v_g_adic, 'Cebola caramelizada', 3, 5);

  insert into public.grupos_opcoes (id_empresa, nome_grupo, minimo_selecao, maximo_selecao, ordem_exibicao)
  values (v_emp, 'Molho', 0, 2, 4) returning id into v_g_molho;
  insert into public.opcoes (id_empresa, id_grupo_opcao, nome_opcao, preco_adicional, ordem_exibicao) values
    (v_emp, v_g_molho, 'Maionese da casa', 0, 1),
    (v_emp, v_g_molho, 'Barbecue', 0, 2),
    (v_emp, v_g_molho, 'Cheddar cremoso', 2, 3);

  -- Lanches
  insert into public.produtos (id_empresa, id_categoria, nome_produto, descricao_produto, preco_produto, ordem_exibicao)
  values (v_emp, v_cat_lanches, 'X-Burger', 'Hambúrguer 150g, queijo, alface e tomate', 22.90, 1) returning id into v_p;
  insert into public.produtos_grupos_opcoes (id_empresa, id_produto, id_grupo_opcao, ordem_exibicao) values
    (v_emp, v_p, v_g_pao, 1), (v_emp, v_p, v_g_ponto, 2), (v_emp, v_p, v_g_adic, 3), (v_emp, v_p, v_g_molho, 4);

  insert into public.produtos (id_empresa, id_categoria, nome_produto, descricao_produto, preco_produto, ordem_exibicao)
  values (v_emp, v_cat_lanches, 'X-Bacon', 'Hambúrguer 150g, bacon crocante, queijo e salada', 27.90, 2) returning id into v_p;
  insert into public.produtos_grupos_opcoes (id_empresa, id_produto, id_grupo_opcao, ordem_exibicao) values
    (v_emp, v_p, v_g_pao, 1), (v_emp, v_p, v_g_ponto, 2), (v_emp, v_p, v_g_adic, 3), (v_emp, v_p, v_g_molho, 4);

  insert into public.produtos (id_empresa, id_categoria, nome_produto, descricao_produto, preco_produto, ordem_exibicao)
  values (v_emp, v_cat_lanches, 'X-Tudo', 'Dois hambúrgueres, bacon, ovo, presunto, queijo e salada', 34.90, 3) returning id into v_p;
  insert into public.produtos_grupos_opcoes (id_empresa, id_produto, id_grupo_opcao, ordem_exibicao) values
    (v_emp, v_p, v_g_pao, 1), (v_emp, v_p, v_g_adic, 2), (v_emp, v_p, v_g_molho, 3);

  -- Porções
  insert into public.produtos (id_empresa, id_categoria, nome_produto, descricao_produto, preco_produto, ordem_exibicao) values
    (v_emp, v_cat_porcoes, 'Batata frita', 'Porção 400g', 19.90, 1),
    (v_emp, v_cat_porcoes, 'Onion rings', 'Porção 300g', 21.90, 2);

  -- Bebidas
  insert into public.produtos (id_empresa, id_categoria, nome_produto, descricao_produto, preco_produto, ordem_exibicao) values
    (v_emp, v_cat_bebidas, 'Refrigerante lata', '350ml', 6.00, 1),
    (v_emp, v_cat_bebidas, 'Suco natural', '500ml', 9.00, 2);

  -- Bairros
  insert into public.bairros_entrega (id_empresa, nome_bairro, taxa_entrega) values
    (v_emp, 'Centro', 5),
    (v_emp, 'Jardim América', 7),
    (v_emp, 'Vila Nova', 8);
end $$;
