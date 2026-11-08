import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export type ClienteBanco = SupabaseClient;

/** Cliente com service role: só no servidor, ignora RLS */
export function clienteServico(): ClienteBanco {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/** Cliente agindo como o usuário logado (respeita RLS) */
export function clienteDoUsuario(req: Request): ClienteBanco {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
}

export const cabecalhosCors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function respostaJson(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cabecalhosCors, "Content-Type": "application/json" },
  });
}

export const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));
