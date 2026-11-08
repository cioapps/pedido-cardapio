/**
 * Chamada pelo banco (pg_net) quando chega pedido novo ou um rascunho do WhatsApp fica pronto.
 * Envia push para todos os celulares da loja.
 * Secrets: PUSH_SEGREDO (igual a privado.configuracoes 'segredo_push'), FIREBASE_SERVICE_ACCOUNT.
 * Deploy: supabase functions deploy notificar-pedido --no-verify-jwt
 */
import { clienteServico, respostaJson } from "../_compartilhado/supabase.ts";
import { enviarPush } from "../_compartilhado/fcm.ts";

interface Corpo {
  id_empresa: number;
  tipo: "pedido" | "rascunho";
  titulo: string;
  texto: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return respostaJson({ erro: "Método não permitido" }, 405);
  const segredo = Deno.env.get("PUSH_SEGREDO");
  if (!segredo || req.headers.get("x-segredo") !== segredo) {
    return respostaJson({ erro: "Não autorizado" }, 401);
  }

  let corpo: Corpo;
  try {
    corpo = await req.json();
  } catch {
    return respostaJson({ erro: "JSON inválido" }, 400);
  }
  if (!corpo.id_empresa || !corpo.titulo) return respostaJson({ erro: "Dados incompletos" }, 400);

  const db = clienteServico();
  const { data: dispositivos } = await db
    .from("dispositivos_lojista")
    .select("id, token_fcm")
    .eq("id_empresa", corpo.id_empresa);

  let enviados = 0;
  const invalidos: number[] = [];
  await Promise.all((dispositivos ?? []).map(async (d) => {
    const r = await enviarPush(d.token_fcm, {
      titulo: corpo.titulo,
      texto: corpo.texto ?? "",
      dados: { tipo: corpo.tipo ?? "pedido", id_empresa: String(corpo.id_empresa) },
    });
    if (r === "ok") enviados++;
    if (r === "invalido") invalidos.push(d.id);
  }));

  // app desinstalado / token trocado: limpa
  if (invalidos.length) await db.from("dispositivos_lojista").delete().in("id", invalidos);

  return respostaJson({ enviados, removidos: invalidos.length });
});
