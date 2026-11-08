/**
 * Lê a conversa do WhatsApp + cardápio e grava/atualiza o rascunho do pedido.
 * Secrets: ANTHROPIC_API_KEY, MODELO_IA (opcional, padrão claude-opus-5-5).
 */
import Anthropic from "npm:@anthropic-ai/sdk@1.6.0";
import type { ClienteBanco } from "./supabase.ts";
import {
  type Cardapio,
  esquemaResposta,
  INSTRUCOES_IA,
  type MensagemConversa,
  type RespostaIa,
  textoCardapio,
  textoConversa,
  validarResposta,
} from "./ia_regras.ts";

const MODELO = Deno.env.get("MODELO_IA") || "claude-opus-5-5";
// Fallback do servidor em caso de recusa: só nos modelos que aceitam o modo "default"
const USA_FALLBACK = /^claude-(opus-5|fable-5|sonnet-5-5)/.test(MODELO);

let cliente: Anthropic | null = null;
const anthropic = () => (cliente ??= new Anthropic({ timeout: 90_000, maxRetries: 2 }));

const JANELA_HORAS = 6;
const MAX_MENSAGENS = 80;

/**
 * Pede ao Claude o pedido estruturado.
 * contexto = dados do contato + rascunho atual + conversa transcrita.
 * Retorna null se o modelo recusar.
 */
export async function extrairPedido(cardapio: Cardapio, contexto: string): Promise<RespostaIa | null> {
  const resposta = await anthropic().beta.messages.create({
    model: MODELO,
    max_tokens: 16000,
    ...(USA_FALLBACK ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const } : {}),
    output_config: {
      effort: "medium",
      format: { type: "json_schema", schema: esquemaResposta as unknown as Record<string, unknown> },
    },
    // Instruções + cardápio são estáveis por loja: ficam em cache
    system: [
      { type: "text", text: INSTRUCOES_IA },
      { type: "text", text: textoCardapio(cardapio), cache_control: { type: "ephemeral" } },
    ],
    messages: [{ role: "user", content: contexto }],
  });

  if (resposta.stop_reason === "refusal") {
    console.warn("IA recusou analisar a conversa", resposta.stop_details);
    return null;
  }
  const bloco = resposta.content.find((b) => b.type === "text");
  if (!bloco || bloco.type !== "text") return null;
  return JSON.parse(bloco.text) as RespostaIa;
}

export async function analisarConversa(db: ClienteBanco, idConversa: number): Promise<void> {
  const { data: conversa } = await db
    .from("conversas_whatsapp")
    .select("id, id_empresa, telefone_contato, nome_contato, ignorar_conversa, empresas(slug_empresa, fuso_horario, modulo_whatsapp_ativo)")
    .eq("id", idConversa)
    .single();
  if (!conversa || conversa.ignorar_conversa) return;
  const empresa = conversa.empresas as unknown as {
    slug_empresa: string;
    fuso_horario: string;
    modulo_whatsapp_ativo: boolean;
  };
  if (!empresa?.modulo_whatsapp_ativo) return;
  // assinatura vencida ou bloqueada: a IA não trabalha (e não gasta)
  const { data: liberada } = await db.rpc("assinatura_liberada", { p_id_empresa: conversa.id_empresa });
  if (!liberada) return;

  // Começa depois do último rascunho fechado (confirmado/descartado) desta conversa
  const { data: ultimoFechado } = await db
    .from("rascunhos_pedido")
    .select("id_ultima_mensagem_analisada")
    .eq("id_conversa", idConversa)
    .in("status_rascunho", ["confirmado", "descartado"])
    .order("id", { ascending: false })
    .limit(1)
    .maybeSingle();

  const desde = new Date(Date.now() - JANELA_HORAS * 3600_000).toISOString();
  let consulta = db
    .from("mensagens_whatsapp")
    .select("id, enviada_pela_loja, tipo_mensagem, texto_mensagem, transcricao_audio, enviada_em")
    .eq("id_conversa", idConversa)
    .gte("enviada_em", desde)
    .order("enviada_em", { ascending: false })
    .limit(MAX_MENSAGENS);
  if (ultimoFechado?.id_ultima_mensagem_analisada) {
    consulta = consulta.gt("id", ultimoFechado.id_ultima_mensagem_analisada);
  }
  const { data: recentes } = await consulta;
  const mensagens = ((recentes ?? []) as (MensagemConversa & { id: number })[]).reverse();
  if (!mensagens.some((m) => !m.enviada_pela_loja)) return; // nada do cliente ainda

  const { data: cardapio } = await db.rpc("obter_cardapio", { p_slug: empresa.slug_empresa });
  if (!cardapio) return;

  const { data: rascunhoAberto } = await db
    .from("rascunhos_pedido")
    .select("id, dados_pedido")
    .eq("id_conversa", idConversa)
    .in("status_rascunho", ["montando", "pronto"])
    .maybeSingle();

  // Endereço do último pedido desse telefone (cliente costuma dizer "mesmo endereço")
  const { data: clienteSalvo } = conversa.telefone_contato
    ? await db
      .from("clientes")
      .select("nome_cliente, ultimo_endereco")
      .eq("id_empresa", conversa.id_empresa)
      .eq("telefone_cliente", conversa.telefone_contato)
      .maybeSingle()
    : { data: null };

  const contexto = [
    `Nome do contato no WhatsApp: ${conversa.nome_contato ?? "desconhecido"}`,
    clienteSalvo
      ? `Cliente já pediu antes: ${clienteSalvo.nome_cliente}. Endereço salvo: ${JSON.stringify(clienteSalvo.ultimo_endereco)}`
      : "Cliente sem pedidos anteriores.",
    rascunhoAberto ? `Rascunho atual (atualize a partir dele): ${JSON.stringify(rascunhoAberto.dados_pedido)}` : "",
    "",
    "CONVERSA:",
    textoConversa(mensagens, empresa.fuso_horario),
  ].filter(Boolean).join("\n");

  const r = await extrairPedido(cardapio as Cardapio, contexto);
  if (!r) return;
  if (!r.e_pedido && !rascunhoAberto) return;

  const v = validarResposta(r, cardapio as Cardapio);
  const ultimaMensagem = mensagens[mensagens.length - 1].id;
  const pronto = r.pedido_fechado && v.pendencias.length === 0 && v.itens.length > 0;

  const registro = {
    status_rascunho: pronto ? "pronto" : "montando",
    dados_pedido: {
      nome_cliente: r.nome_cliente,
      telefone_cliente: conversa.telefone_contato,
      logradouro: r.logradouro,
      numero_endereco: r.numero_endereco,
      complemento: r.complemento,
      ponto_referencia: r.ponto_referencia,
      id_bairro_entrega: v.idBairro,
      forma_pagamento: r.forma_pagamento,
      troco_para: r.forma_pagamento === "dinheiro" ? r.troco_para : null,
      observacao_pedido: r.observacao_pedido,
      itens: v.itens,
    },
    pendencias: v.pendencias,
    resumo_ia: r.resumo,
    valor_estimado: v.valorEstimado,
    id_ultima_mensagem_analisada: ultimaMensagem,
  };

  if (rascunhoAberto) {
    await db.from("rascunhos_pedido").update(registro).eq("id", rascunhoAberto.id)
      .in("status_rascunho", ["montando", "pronto"]); // não mexe se o lojista confirmou enquanto isso
    return;
  }
  const { error } = await db.from("rascunhos_pedido").insert({
    ...registro,
    id_empresa: conversa.id_empresa,
    id_conversa: idConversa,
  });
  // corrida: outra análise criou o rascunho ao mesmo tempo -> atualiza o aberto
  if (error?.code === "23505") {
    await db.from("rascunhos_pedido").update(registro).eq("id_conversa", idConversa)
      .in("status_rascunho", ["montando", "pronto"]);
  } else if (error) {
    throw error;
  }
}
