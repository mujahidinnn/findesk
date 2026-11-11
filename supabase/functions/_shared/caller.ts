import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { HttpError } from "./cors.ts";

export interface Caller {
  id: string;
  rank: number;
  /** Service-role client. It skips RLS and the rank trigger, so callers re-check rank themselves. */
  admin: SupabaseClient;
}

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}

export async function requireCaller(req: Request, feature: string, action: string): Promise<Caller> {
  const auth = req.headers.get("Authorization");
  if (!auth) throw new HttpError(401, "Missing Authorization header");
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data: { user } } = await client.auth.getUser();
  if (!user) throw new HttpError(401, "Invalid session");

  const { data: allowed } = await client.rpc("has_permission", { p_feature_key: feature, p_action: action });
  if (allowed !== true) throw new HttpError(403, "Not allowed");

  const admin = adminClient();
  const { data: profile } = await admin.from("profiles").select("role:m_roles(rank)").eq("id", user.id).maybeSingle();
  const rank = (profile?.role as { rank?: number } | null)?.rank ?? Infinity;
  return { id: user.id, rank, admin };
}

export async function requireTargetBelow(caller: Caller, userId: string) {
  const { data: target } = await caller.admin
    .from("profiles")
    .select("is_superadmin, role:m_roles(rank)")
    .eq("id", userId)
    .maybeSingle();
  if (!target || target.is_superadmin) throw new HttpError(404, "User not found");
  const rank = (target.role as { rank?: number } | null)?.rank ?? Infinity;
  if (rank <= caller.rank) throw new HttpError(403, "You can only manage users below your own role");
}
