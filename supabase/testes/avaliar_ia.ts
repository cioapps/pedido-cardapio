/**
 * Avaliação da IA de pedidos com conversas de exemplo (chama a API do Claude de verdade: tem custo).
 *
 *   cd supabase/functions
 *   ANTHROPIC_API_KEY=... deno run --allow-env --allow-net --allow-read ../testes/avaliar_ia.ts
 *
 * Opcional: MODELO_IA=claude-sonnet-5-5 para comparar custo x acerto.
 */
import { extrairPedido } from "../functions/_compartilhado/ia.ts";
import { type Cardapio, type MensagemConversa, textoConversa, validarResposta } from "../functions/_compartilhado/ia_regras.ts";

interface Caso {
  nome: string;
  conversa: { de: "cliente" | "loja"; texto?: string; audio?: string }[];
  esperado: {
    e_pedido: boolean;
    pedido_fechado?: boolean;
    itens: { produto: string; quantidade: number; opcoes: string[]; observacao?: boolean }[];
    bairro?: string | null;
    pagamento?: string;
    troco?: number;
    nome?: boolean;
    pendencia_contem?: string[];
  };
}

const pasta = new URL("./conversas/", import.meta.url);
const cardapio = JSON.parse(await Deno.readTextFile(new URL("cardapio_exemplo.json", pasta))) as Cardapio;
const casos = JSON.parse(await Deno.readTextFile(new URL("casos.json", pasta))) as Caso[];
const filtro = Deno.args[0];

const nomeProduto = new Map<number, string>();
const nomeOpcao = new Map<number, string>();
for (const cat of cardapio.categorias) {
  for (const p of cat.produtos) {
    nomeProduto.set(p.id, p.nome_produto);
    for (const g of p.grupos) for (const o of g.opcoes) nomeOpcao.set(o.id, o.nome_opcao);
  }
}
const bairroPorId = new Map(cardapio.bairros.map((b) => [b.id, b.nome_bairro]));

let acertos = 0;
let total = 0;
for (const caso of casos.filter((c) => !filtro || c.nome.includes(filtro))) {
  total++;
  const inicio = Date.parse("2026-11-07T22:00:00Z");
  const mensagens: MensagemConversa[] = caso.conversa.map((m, i) => ({
    enviada_pela_loja: m.de === "loja",
    tipo_mensagem: m.audio ? "audio" : "texto",
    texto_mensagem: m.texto ?? null,
    transcricao_audio: m.audio ?? null,
    enviada_em: new Date(inicio + i * 60_000).toISOString(),
  }));
  const contexto = ["Nome do contato no WhatsApp: desconhecido", "Cliente sem pedidos anteriores.", "", "CONVERSA:", textoConversa(mensagens)].join("\n");

  const r = await extrairPedido(cardapio, contexto);
  const falhas: string[] = [];
  if (!r) {
    falhas.push("IA recusou");
  } else {
    const v = validarResposta(r, cardapio);
    const e = caso.esperado;
    if (r.e_pedido !== e.e_pedido) falhas.push(`e_pedido=${r.e_pedido}`);
    if (e.pedido_fechado !== undefined && r.pedido_fechado !== e.pedido_fechado) falhas.push(`pedido_fechado=${r.pedido_fechado}`);

    const obtidos = v.itens.map((i) => ({
      produto: nomeProduto.get(i.id_produto),
      quantidade: i.quantidade,
      opcoes: i.opcoes.map((o) => nomeOpcao.get(o.id_opcao)).sort(),
      observacao: i.observacao_item !== "",
    }));
    const chave = (x: { produto?: string; quantidade: number; opcoes: (string | undefined)[] }) =>
      `${x.quantidade}x ${x.produto} [${[...x.opcoes].sort().join(", ")}]`;
    const esperados = e.itens.map(chave).sort();
    const recebidos = obtidos.map(chave).sort();
    if (JSON.stringify(esperados) !== JSON.stringify(recebidos)) {
      falhas.push(`itens: esperado ${esperados.join(" | ")} / veio ${recebidos.join(" | ")}`);
    }
    for (const item of e.itens.filter((i) => i.observacao)) {
      if (!obtidos.some((o) => o.produto === item.produto && o.observacao)) falhas.push(`${item.produto} sem observação`);
    }
    if (e.bairro !== undefined && (v.idBairro ? bairroPorId.get(v.idBairro) : null) !== e.bairro) {
      falhas.push(`bairro=${v.idBairro ? bairroPorId.get(v.idBairro) : null}`);
    }
    if (e.pagamento && r.forma_pagamento !== e.pagamento) falhas.push(`pagamento=${r.forma_pagamento}`);
    if (e.troco && Number(r.troco_para) !== e.troco) falhas.push(`troco=${r.troco_para}`);
    if (e.nome && !r.nome_cliente) falhas.push("sem nome");
    for (const termo of e.pendencia_contem ?? []) {
      if (!v.pendencias.some((p) => p.toLowerCase().includes(termo))) falhas.push(`pendência sem "${termo}": ${v.pendencias.join("; ")}`);
    }
  }
  if (falhas.length === 0) acertos++;
  console.log(`${falhas.length === 0 ? "✓" : "✗"} ${caso.nome}${falhas.length ? `\n    ${falhas.join("\n    ")}` : ""}`);
}
console.log(`\n${acertos}/${total} conversas corretas (modelo ${Deno.env.get("MODELO_IA") || "claude-opus-5-5"})`);
