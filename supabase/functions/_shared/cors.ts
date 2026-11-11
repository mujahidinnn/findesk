const ALLOWED_ORIGINS = new Set(["https://findesk.mujahidin.my.id", "http://localhost:8080"]);

export function corsHeaders(req: Request | null): Record<string, string> {
  const origin = req?.headers.get("Origin") ?? "";
  if (!ALLOWED_ORIGINS.has(origin)) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

export function jsonResponse(req: Request | null, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export async function readJson(req: Request, maxBytes = 100_000): Promise<unknown> {
  const text = await req.text();
  if (new TextEncoder().encode(text).length > maxBytes) throw new HttpError(413, "Request body too large");
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, "Body must be JSON");
  }
}

type Logger = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<unknown> };

export async function errorResponse(req: Request | null, err: unknown, source: string, log?: Logger): Promise<Response> {
  if (err instanceof HttpError) return jsonResponse(req, { error: err.message }, err.status);
  console.error(err);
  const message = err instanceof Error ? err.message : String(err);
  try {
    await log?.rpc("log_client_error", { p_source: `edge.${source}`, p_message: message, p_context: {} });
  } catch {
    // Logging must never hide the original failure.
  }
  return jsonResponse(req, { error: "Unexpected error" }, 500);
}

export function safeEqual(a: string | null, b: string): boolean {
  if (a == null) return false;
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < y.length; i++) diff |= (x[i] ?? 0) ^ y[i];
  return diff === 0;
}
