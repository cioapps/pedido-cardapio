/**
 * Envio de push pelo Firebase Cloud Messaging (API HTTP v1).
 * Secret: FIREBASE_SERVICE_ACCOUNT = conteúdo do JSON da conta de serviço do Firebase.
 */

interface ContaServico {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

let contaCache: ContaServico | null = null;
let acessoCache: { token: string; expira: number } | null = null;

function conta(): ContaServico {
  if (contaCache) return contaCache;
  const bruto = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!bruto) throw new Error("FIREBASE_SERVICE_ACCOUNT não configurado");
  contaCache = JSON.parse(bruto) as ContaServico;
  return contaCache;
}

const base64url = (dados: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof dados === "string"
    ? new TextEncoder().encode(dados)
    : dados instanceof Uint8Array
    ? dados
    : new Uint8Array(dados);
  let binario = "";
  for (const b of bytes) binario += String.fromCharCode(b);
  return btoa(binario).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function chavePrivada(pem: string): Promise<CryptoKey> {
  const corpo = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(corpo), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/** Token OAuth de acesso (válido ~1h, guardado em memória) */
async function tokenAcesso(): Promise<string> {
  if (acessoCache && acessoCache.expira > Date.now() + 60_000) return acessoCache.token;
  const c = conta();
  const agora = Math.floor(Date.now() / 1000);
  const uri = c.token_uri ?? "https://oauth2.googleapis.com/token";
  const cabecalho = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = base64url(JSON.stringify({
    iss: c.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: uri,
    iat: agora,
    exp: agora + 3600,
  }));
  const assinatura = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    await chavePrivada(c.private_key),
    new TextEncoder().encode(`${cabecalho}.${corpo}`),
  );
  const jwt = `${cabecalho}.${corpo}.${base64url(assinatura)}`;

  const r = await fetch(uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`OAuth Firebase: ${r.status} ${JSON.stringify(j)}`);
  acessoCache = { token: j.access_token, expira: Date.now() + (j.expires_in ?? 3600) * 1000 };
  return acessoCache.token;
}

export interface Aviso {
  titulo: string;
  texto: string;
  dados?: Record<string, string>;
}

/** Canal Android criado pelo app, com o som de alarme (ver app_lojista/lib/servicos/notificacoes_servico.dart) */
export const CANAL_PEDIDOS = "pedidos_alarme_v1";

/**
 * Envia para um token. Retorna "ok", "invalido" (token morto: apagar) ou "erro".
 */
export async function enviarPush(token: string, aviso: Aviso): Promise<"ok" | "invalido" | "erro"> {
  const c = conta();
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${c.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await tokenAcesso()}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: aviso.titulo, body: aviso.texto },
        data: aviso.dados ?? {},
        android: {
          priority: "HIGH",
          ttl: "600s",
          notification: {
            channel_id: CANAL_PEDIDOS,
            sound: "alerta_longo",
            notification_priority: "PRIORITY_MAX",
            visibility: "PUBLIC",
            default_vibrate_timings: true,
            tag: aviso.dados?.tipo ?? "pedido",
          },
        },
      },
    }),
  });
  if (r.ok) return "ok";
  const erro = await r.text();
  if (r.status === 404 || erro.includes("UNREGISTERED") || erro.includes("registration-token-not-registered")) {
    return "invalido";
  }
  console.error("FCM falhou", r.status, erro);
  return "erro";
}
