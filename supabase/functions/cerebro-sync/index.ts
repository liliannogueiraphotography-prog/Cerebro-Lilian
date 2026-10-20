import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedEmail = "lilian.nogueira@live.com";
const allowedOrigins = new Set([
  "https://cerebro-lilian-preview.lilian-nogueira.chatgpt.site",
  "http://localhost:5173",
  "http://127.0.0.1:5173",
]);

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin") ?? "";
  const cors: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (allowedOrigins.has(origin)) cors["Access-Control-Allow-Origin"] = origin;
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return reply({ error: "Método não permitido." }, 405, cors);
  if (origin && !allowedOrigins.has(origin)) return reply({ error: "Origem não autorizada." }, 403, cors);

  try {
    const authorization = request.headers.get("authorization") ?? "";
    const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!token) return reply({ error: "Entre no painel para continuar." }, 401, cors);

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return reply({ error: "A conexão do Cérebro não está disponível." }, 503, cors);
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: { user }, error: authError } = await admin.auth.getUser(token);
    if (authError || !user || user.email?.toLowerCase() !== allowedEmail || !user.email_confirmed_at) {
      return reply({ error: "Esta conta não tem acesso a este Cérebro privado." }, 403, cors);
    }

    const body = await request.json().catch(() => null) as { action?: string; state?: unknown } | null;
    if (body?.action === "brain-graph") {
      const { data, error } = await admin.rpc("get_brain_graph", { max_nodes: 250, include_archived: false });
      if (error) throw error;
      return reply(data ?? { nodes: [], relations: [] }, 200, cors);
    }
    if (body?.action === "get-executor-state") {
      const { data, error } = await admin.rpc("brain_get_executor_state", { p_owner_user_id: user.id });
      if (error) throw error;
      return reply({ state: data ?? null }, 200, cors);
    }
    if (body?.action === "save-executor-state") {
      if (!body.state || typeof body.state !== "object" || Array.isArray(body.state)) {
        return reply({ error: "O plano enviado não tem um formato válido." }, 400, cors);
      }
      const { data, error } = await admin.rpc("brain_save_executor_state", { p_owner_user_id: user.id, p_state: body.state });
      if (error) throw error;
      return reply(data ?? { saved: true }, 200, cors);
    }
    return reply({ error: "Ação desconhecida." }, 400, cors);
  } catch (error) {
    console.error("cerebro-sync", error);
    return reply({ error: "Não foi possível concluir a sincronização. Tente novamente." }, 500, cors);
  }
});

function reply(body: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
