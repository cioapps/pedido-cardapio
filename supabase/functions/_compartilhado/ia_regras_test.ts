// deno test supabase/functions/_compartilhado/ia_regras_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { type Cardapio, type RespostaIa, textoCardapio, textoConversa, validarResposta } from "./ia_regras.ts";

const cardapio: Cardapio = {
  empresa: { nome_empresa: "Lanche Exemplo", pedido_minimo: 20 },
  bairros: [{ id: 1, nome_bairro: "Centro", taxa_entrega: 5 }],
  categorias: [{
    nome_categoria: "Lanches",
    produtos: [
      {
        id: 10,
        nome_produto: "X-Burger",
        descricao_produto: "Hambúrguer 150g",
        preco_produto: 22.9,
        grupos: [
          { id: 1, nome_grupo: "Escolha o pão", minimo_selecao: 1, maximo_selecao: 1, opcoes: [
            { id: 100, nome_opcao: "Pão de hambúrguer", preco_adicional: 0 },
            { id: 101, nome_opcao: "Pão australiano", preco_adicional: 2 },
          ] },
          { id: 2, nome_grupo: "Adicionais", minimo_selecao: 0, maximo_selecao: 10, opcoes: [
            { id: 200, nome_opcao: "Bacon", preco_adicional: 4 },
          ] },
        ],
      },
      { id: 11, nome_produto: "Refrigerante lata", descricao_produto: null, preco_produto: 6, grupos: [] },
    ],
  }],
};

const base: RespostaIa = {
  e_pedido: true, pedido_fechado: true, resumo: "", pendencias: [], itens: [],
  nome_cliente: "Maria", logradouro: "Rua A", numero_endereco: "10", complemento: null, ponto_referencia: null,
  id_bairro_entrega: 1, forma_pagamento: "pix", troco_para: null, observacao_pedido: null,
};

Deno.test("cardápio no prompt traz IDs, regras e taxas", () => {
  const t = textoCardapio(cardapio);
  assert(t.includes("[produto 10] X-Burger — R$ 22,90"));
  assert(t.includes('grupo "Escolha o pão" (obrigatório, escolher 1)'));
  assert(t.includes("[opcao 101] Pão australiano +R$ 2,00"));
  assert(t.includes("[bairro 1] Centro — R$ 5,00"));
});

Deno.test("conversa marca quem falou e usa a transcrição do áudio", () => {
  const t = textoConversa([
    { enviada_pela_loja: false, tipo_mensagem: "texto", texto_mensagem: "oi", transcricao_audio: null, enviada_em: "2026-11-07T22:00:00Z" },
    { enviada_pela_loja: true, tipo_mensagem: "texto", texto_mensagem: "boa noite!", transcricao_audio: null, enviada_em: "2026-11-07T22:01:00Z" },
    { enviada_pela_loja: false, tipo_mensagem: "audio", texto_mensagem: null, transcricao_audio: "quero um x-burger", enviada_em: "2026-11-07T22:02:00Z" },
  ]);
  assertEquals(t.split("\n"), [
    "[19:00] CLIENTE: oi",
    "[19:01] LOJA: boa noite!",
    "[19:02] CLIENTE: (áudio) quero um x-burger",
  ]);
});

Deno.test("pedido completo: calcula valor e não deixa pendência", () => {
  const v = validarResposta({
    ...base,
    itens: [
      { id_produto: 10, quantidade: 2, observacao_item: "sem cebola", opcoes: [{ id_opcao: 101, quantidade: 1 }, { id_opcao: 200, quantidade: 1 }] },
      { id_produto: 11, quantidade: 1, observacao_item: "", opcoes: [] },
    ],
  }, cardapio);
  // (22,90 + 2 + 4) * 2 + 6 + 5 de taxa
  assertEquals(v.valorEstimado, 68.8);
  assertEquals(v.pendencias, []);
  assertEquals(v.itens.length, 2);
});

Deno.test("descarta produto e opção inexistentes", () => {
  const v = validarResposta({
    ...base,
    itens: [
      { id_produto: 999, quantidade: 1, observacao_item: "", opcoes: [] },
      { id_produto: 11, quantidade: 1, observacao_item: "", opcoes: [{ id_opcao: 200, quantidade: 1 }] },
    ],
  }, cardapio);
  assertEquals(v.itens, [{ id_produto: 11, quantidade: 1, observacao_item: "", opcoes: [] }]);
  assert(v.pendencias.some((p) => p.includes("não está no cardápio")));
});

Deno.test("grupo obrigatório sem escolha vira pendência", () => {
  const v = validarResposta({
    ...base,
    itens: [{ id_produto: 10, quantidade: 1, observacao_item: "", opcoes: [] }],
  }, cardapio);
  assertEquals(v.pendencias, ['X-Burger: falta escolher "Escolha o pão"']);
});

Deno.test("dados de entrega faltando viram pendências (sem duplicar as da IA)", () => {
  const v = validarResposta({
    ...base,
    pendencias: ["Falta confirmar o bairro"],
    nome_cliente: null, id_bairro_entrega: 77, forma_pagamento: null,
    itens: [{ id_produto: 11, quantidade: 1, observacao_item: "", opcoes: [] }],
  }, cardapio);
  assertEquals(v.idBairro, null);
  assertEquals(v.pendencias, ["Falta confirmar o bairro", "Falta o nome do cliente", "Falta a forma de pagamento"]);
});

Deno.test("conversa que não é pedido não gera pendências", () => {
  const v = validarResposta({ ...base, e_pedido: false, nome_cliente: null, forma_pagamento: null }, cardapio);
  assertEquals(v.pendencias, []);
  assertEquals(v.itens, []);
});
