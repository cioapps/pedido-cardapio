/**
 * Conexão do WhatsApp da loja (chamada pelo painel e pelo app, com o login do lojista).
 * POST { acao: "conectar", telefone?: string }  -> cria a instância se precisar, liga o webhook
 *                                                 e devolve QR Code ou código de pareamento
 * POST { acao: "status" }                       -> status atual (+ QR/código enquanto conecta)
 * POST { acao: "desconectar" }
 */
import { cabecalhosCors, clienteDoUsuario, clienteServico, respostaJson } from "../_compartilhado/supabase.ts";
import * as uazapi from "../_compartilhado/uazapi.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cabecalhosCors });
  if (req.method !== "POST") return respostaJson({ erro: "Método não permitido" }, 405);

  try {
    // Quem está chamando?
    const { data: usuario } = await clienteDoUsuario(req).auth.getUser();
    if (!usuario.user) return respostaJson({ erro: "Faça login novamente" }, 401);

    const db = clienteServico();
    const { data: vinculo } = await db
      .from("usuarios_empresa")
      .select("id_empresa, empresas(slug_empresa, modulo_whatsapp_ativo)")
      .eq("id_usuario_auth", usuario.user.id)
      .order("id")
      .limit(1)
      .maybeSingle();
    if (!vinculo) return respostaJson({ erro: "Usuário sem loja" }, 403);
    const empresa = vinculo.empresas as unknown as { slug_empresa: string; modulo_whatsapp_ativo: boolean };
    if (!empresa.modulo_whatsapp_ativo) {
      return respostaJson({ erro: "O módulo WhatsApp não está ativo para esta loja" }, 403);
    }

    const { acao, telefone } = (await req.json().catch(() => ({}))) as { acao?: string; telefone?: string };

    let { data: conexao } = await db
      .from("conexoes_whatsapp")
      .select("id, token_instancia, segredo_webhook")
      .eq("id_empresa", vinculo.id_empresa)
      .maybeSingle();

    if (acao === "conectar") {
      if (!conexao) {
        const nome = `loja-${vinculo.id_empresa}-${empresa.slug_empresa}`.slice(0, 60);
        const token = await uazapi.criarInstancia(nome);
        const { data: nova, error } = await db
          .from("conexoes_whatsapp")
          .insert({ id_empresa: vinculo.id_empresa, nome_instancia: nome, token_instancia: token })
          .select("id, token_instancia, segredo_webhook")
          .single();
        if (error) throw error;
        conexao = nova;
      }
      const urlWebhook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-webhook?s=${conexao!.segredo_webhook}`;
      await uazapi.configurarWebhook(conexao!.token_instancia, urlWebhook);
      const digitos = (telefone ?? "").replace(/\D/g, "");
      await uazapi.conectar(conexao!.token_instancia, digitos ? (digitos.length <= 11 ? `55${digitos}` : digitos) : undefined);
    }

    if (!conexao) return respostaJson({ status_conexao: "sem_conexao" });

    if (acao === "desconectar") {
      await uazapi.desconectar(conexao.token_instancia);
    }

    const status = await uazapi.obterStatus(conexao.token_instancia);
    await db.from("conexoes_whatsapp").update({
      status_conexao: status.status,
      ...(status.numero ? { numero_conectado: status.numero } : {}),
    }).eq("id", conexao.id);

    return respostaJson({
      status_conexao: status.status,
      numero_conectado: status.numero,
      qrcode: status.status === "connected" ? null : status.qrcode,
      codigo_pareamento: status.status === "connected" ? null : status.paircode,
    });
  } catch (e) {
    console.error("whatsapp-conexao", e);
    const mensagem = e instanceof uazapi.ErroUazapi
      ? "O servidor do WhatsApp não respondeu como esperado. Tente novamente."
      : "Erro inesperado ao falar com o WhatsApp.";
    return respostaJson({ erro: mensagem }, 502);
  }
});
