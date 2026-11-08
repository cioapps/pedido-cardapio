/**
 * Chamadas à uazapiGO (servidor próprio).
 * Secrets: UAZAPI_URL, UAZAPI_ADMIN_TOKEN e (opcional) OPENAI_API_KEY para transcrever áudio.
 */

const baseUrl = () => (Deno.env.get("UAZAPI_URL") ?? "").replace(/\/+$/, "");

interface OpcoesChamada {
  metodo?: "GET" | "POST" | "DELETE";
  token?: string;
  admin?: boolean;
  corpo?: unknown;
}

export class ErroUazapi extends Error {
  constructor(public status: number, mensagem: string) {
    super(mensagem);
  }
}

async function chamar<T>(caminho: string, opcoes: OpcoesChamada = {}): Promise<T> {
  const cabecalhos: Record<string, string> = { "Content-Type": "application/json" };
  if (opcoes.admin) cabecalhos.admintoken = Deno.env.get("UAZAPI_ADMIN_TOKEN") ?? "";
  if (opcoes.token) cabecalhos.token = opcoes.token;

  const resposta = await fetch(`${baseUrl()}${caminho}`, {
    method: opcoes.metodo ?? "POST",
    headers: cabecalhos,
    body: opcoes.corpo === undefined ? undefined : JSON.stringify(opcoes.corpo),
    signal: AbortSignal.timeout(30_000),
  });
  const texto = await resposta.text();
  if (!resposta.ok) {
    throw new ErroUazapi(resposta.status, `uazapi ${caminho} ${resposta.status}: ${texto.slice(0, 300)}`);
  }
  return (texto ? JSON.parse(texto) : {}) as T;
}

export interface StatusInstancia {
  status: string; // disconnected | connecting | connected | hibernated
  qrcode: string | null;
  paircode: string | null;
  numero: string | null;
}

interface RespostaStatus {
  instance?: { status?: string; qrcode?: string; paircode?: string; owner?: string };
  status?: { connected?: boolean; jid?: { user?: string } | string | null };
}

function lerStatus(r: RespostaStatus): StatusInstancia {
  const jid = r.status?.jid;
  const numero = typeof jid === "string" ? jid.split("@")[0].split(":")[0] : jid?.user ?? null;
  return {
    status: r.instance?.status ?? (r.status?.connected ? "connected" : "disconnected"),
    qrcode: r.instance?.qrcode || null,
    paircode: r.instance?.paircode || null,
    numero: numero || null,
  };
}

/** Cria a instância (admintoken) e devolve o token dela */
export async function criarInstancia(nome: string): Promise<string> {
  const r = await chamar<{ token?: string; instance?: { token?: string } }>("/instance/create", {
    admin: true,
    corpo: { name: nome },
  });
  const token = r.token ?? r.instance?.token;
  if (!token) throw new Error("uazapi não retornou o token da instância");
  return token;
}

/** Sem telefone: QR Code. Com telefone: código de pareamento. */
export async function conectar(token: string, telefone?: string): Promise<void> {
  const corpo: Record<string, unknown> = { systemName: "Cardápio Online" };
  if (telefone) corpo.phone = telefone;
  try {
    await chamar("/instance/connect", { token, corpo });
  } catch (e) {
    // 409 = já existe uma tentativa de conexão em andamento: seguimos para o status
    if (!(e instanceof ErroUazapi && e.status === 409)) throw e;
  }
}

export async function obterStatus(token: string): Promise<StatusInstancia> {
  return lerStatus(await chamar<RespostaStatus>("/instance/status", { metodo: "GET", token }));
}

export async function desconectar(token: string): Promise<void> {
  await chamar("/instance/disconnect", { token, corpo: {} });
}

/**
 * Webhook com as mensagens do cliente E do lojista (não exclui fromMe).
 * Grupos ficam de fora.
 */
export async function configurarWebhook(token: string, url: string): Promise<void> {
  await chamar("/webhook", {
    token,
    corpo: {
      enabled: true,
      url,
      events: ["messages", "connection"],
      excludeMessages: ["isGroupYes"],
      addUrlEvents: false,
      addUrlTypesMessages: false,
    },
  });
}

/** Transcreve um áudio pelo /message/download. Retorna null se não conseguir. */
export async function transcreverAudio(token: string, idMensagem: string): Promise<string | null> {
  const corpo: Record<string, unknown> = { id: idMensagem, transcribe: true, generate_mp3: true };
  const chaveOpenAi = Deno.env.get("OPENAI_API_KEY");
  if (chaveOpenAi) corpo.openai_apikey = chaveOpenAi;
  const r = await chamar<{ transcription?: string }>("/message/download", { token, corpo });
  return r.transcription?.trim() || null;
}

export async function enviarTexto(token: string, numero: string, texto: string): Promise<void> {
  await chamar("/send/text", { token, corpo: { number: numero, text: texto } });
}
