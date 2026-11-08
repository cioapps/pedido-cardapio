/**
 * Recebe os eventos da uazapiGO (URL: /functions/v1/whatsapp-webhook?s=<segredo_webhook>).
 * Responde 200 na hora e processa em segundo plano:
 *  - connection: atualiza o status da conexão
 *  - messages:   grava conversa/mensagem (cliente e loja), transcreve áudio
 *                e, após um intervalo sem mensagens novas, pede para a IA montar o pedido.
 */
import { analisarConversa } from "../_compartilhado/ia.ts";
import { clienteServico, esperar } from "../_compartilhado/supabase.ts";
import { transcreverAudio } from "../_compartilhado/uazapi.ts";

declare const EdgeRuntime: { waitUntil(promessa: Promise<unknown>): void };

const ESPERA_ANALISE_MS = Number(Deno.env.get("ESPERA_ANALISE_MS") ?? 20_000);

interface MensagemUazapi {
  id?: string;
  messageid?: string;
  chatid?: string;
  sender?: string;
  sender_pn?: string;
  senderName?: string;
  isGroup?: boolean;
  fromMe?: boolean;
  messageType?: string;
  mediaType?: string;
  messageTimestamp?: number;
  text?: string;
  content?: unknown;
}

interface EventoUazapi {
  EventType?: string;
  token?: string;
  owner?: string;
  message?: MensagemUazapi;
  chat?: { wa_chatid?: string; name?: string; wa_name?: string; phone?: string };
  instance?: { status?: string };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");
  const segredo = new URL(req.url).searchParams.get("s") ?? "";
  const evento = (await req.json().catch(() => null)) as EventoUazapi | null;
  if (segredo && evento) {
    EdgeRuntime.waitUntil(
      processar(segredo, evento).catch((e) => console.error("erro no webhook whatsapp", e)),
    );
  }
  return new Response("ok");
});

const soDigitos = (t?: string | null) => (t ?? "").replace(/\D/g, "");

function tipoDaMensagem(m: MensagemUazapi): string {
  const tipo = `${m.messageType ?? ""} ${m.mediaType ?? ""}`.toLowerCase();
  const mime = String((m.content as { mimetype?: string } | null)?.mimetype ?? "").toLowerCase();
  if (tipo.includes("audio") || tipo.includes("ptt") || mime.startsWith("audio")) return "audio";
  if (tipo.includes("image")) return "imagem";
  if (tipo.includes("location")) return "localizacao";
  if (tipo.includes("sticker")) return "figurinha";
  if (tipo.includes("video")) return "video";
  if (tipo.includes("document")) return "documento";
  return "texto";
}

/** Número do contato: JID @s.whatsapp.net; para @lid tenta os campos alternativos */
function telefoneDoContato(e: EventoUazapi, m: MensagemUazapi): string | null {
  const chat = m.chatid ?? e.chat?.wa_chatid ?? "";
  if (chat.endsWith("@s.whatsapp.net")) return soDigitos(chat.split("@")[0].split(":")[0]);
  const alternativo = soDigitos(m.sender_pn?.split("@")[0]) || soDigitos(e.chat?.phone);
  return alternativo || null;
}

async function processar(segredo: string, evento: EventoUazapi) {
  const db = clienteServico();
  const { data: conexao } = await db
    .from("conexoes_whatsapp")
    .select("id, id_empresa, token_instancia, ia_ativa, transcrever_audio, empresas(modulo_whatsapp_ativo)")
    .eq("segredo_webhook", segredo)
    .maybeSingle();
  if (!conexao) return;
  // o token do evento precisa ser o da instância desta loja
  if (!evento.token || evento.token !== conexao.token_instancia) {
    console.warn("webhook whatsapp com token inválido para a conexão", conexao.id);
    return;
  }

  if (evento.EventType === "connection") {
    await db.from("conexoes_whatsapp").update({
      status_conexao: evento.instance?.status ?? "disconnected",
      ...(evento.instance?.status === "connected" && evento.owner ? { numero_conectado: soDigitos(evento.owner) } : {}),
    }).eq("id", conexao.id);
    return;
  }

  if (evento.EventType !== "messages" || !evento.message) return;
  const moduloAtivo = (conexao.empresas as unknown as { modulo_whatsapp_ativo: boolean })?.modulo_whatsapp_ativo;
  if (!moduloAtivo) return;

  const m = evento.message;
  const chatId = m.chatid ?? evento.chat?.wa_chatid;
  if (!chatId || m.isGroup || chatId.endsWith("@g.us") || chatId.endsWith("@newsletter") || chatId === "status@broadcast") {
    return;
  }
  const idExterno = m.messageid ?? m.id;
  if (!idExterno) return;

  const fromMe = Boolean(m.fromMe);
  const enviadaEm = m.messageTimestamp
    ? new Date(m.messageTimestamp > 1e12 ? m.messageTimestamp : m.messageTimestamp * 1000).toISOString()
    : new Date().toISOString();

  // Conversa (nome do contato só vem nas mensagens do cliente)
  const { data: conversa, error: erroConversa } = await db
    .from("conversas_whatsapp")
    .upsert({
      id_empresa: conexao.id_empresa,
      chat_id: chatId,
      telefone_contato: telefoneDoContato(evento, m),
      ultima_mensagem_em: enviadaEm,
      ...(!fromMe && (m.senderName || evento.chat?.name)
        ? { nome_contato: m.senderName || evento.chat?.name }
        : {}),
    }, { onConflict: "id_empresa,chat_id" })
    .select("id, ignorar_conversa")
    .single();
  if (erroConversa || !conversa) throw erroConversa;

  const tipo = tipoDaMensagem(m);
  const { data: inserida } = await db
    .from("mensagens_whatsapp")
    .upsert({
      id_empresa: conexao.id_empresa,
      id_conversa: conversa.id,
      id_mensagem_externa: idExterno,
      enviada_pela_loja: fromMe,
      tipo_mensagem: tipo,
      texto_mensagem: m.text?.slice(0, 4000) || null,
      enviada_em: enviadaEm,
    }, { onConflict: "id_empresa,id_mensagem_externa", ignoreDuplicates: true })
    .select("id")
    .maybeSingle();
  if (!inserida) return; // reentrega do mesmo evento

  if (tipo === "audio" && conexao.transcrever_audio) {
    try {
      const transcricao = await transcreverAudio(conexao.token_instancia, idExterno);
      if (transcricao) {
        await db.from("mensagens_whatsapp").update({ transcricao_audio: transcricao }).eq("id", inserida.id);
      }
    } catch (e) {
      console.warn("falha ao transcrever áudio", e);
    }
  }

  if (!conexao.ia_ativa || conversa.ignorar_conversa) return;

  // Debounce: só analisa se nenhuma mensagem nova chegou nesse intervalo
  await esperar(ESPERA_ANALISE_MS);
  const { data: maisRecente } = await db
    .from("mensagens_whatsapp")
    .select("id")
    .eq("id_conversa", conversa.id)
    .order("id", { ascending: false })
    .limit(1)
    .single();
  if (maisRecente?.id !== inserida.id) return;

  await analisarConversa(db, conversa.id);
}
