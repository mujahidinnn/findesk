import { z } from "npm:zod@4";
import { corsHeaders, errorResponse, HttpError, jsonResponse, readJson } from "../_shared/cors.ts";
import { adminClient, requireCaller } from "../_shared/caller.ts";

const Body = z.object({
  email: z.email().max(254),
  password: z.string().regex(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,72}$/, "Password needs 8+ characters with upper case, lower case and a number"),
  full_name: z.string().trim().min(1).max(120),
  role_id: z.number().int(),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const caller = await requireCaller(req, "users", "create");
    const parsed = Body.safeParse(await readJson(req));
    if (!parsed.success) throw new HttpError(400, parsed.error.issues[0]?.message ?? "Invalid body");
    const body = parsed.data;
    const { admin } = caller;

    const { data: role } = await admin.from("m_roles").select("id, rank").eq("id", body.role_id).maybeSingle();
    if (!role) throw new HttpError(400, "Unknown role_id");
    if (role.rank <= caller.rank) throw new HttpError(403, "You cannot assign a role at or above your own rank");

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: body.email,
      password: body.password,
      email_confirm: true,
      user_metadata: { full_name: body.full_name },
    });
    if (createErr) throw new HttpError(400, createErr.message);

    const { error: updateErr } = await admin
      .from("profiles")
      .update({ full_name: body.full_name, role_id: body.role_id })
      .eq("id", created.user.id);
    if (updateErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      throw updateErr;
    }

    await admin.from("t_audit_log").insert({
      actor_id: caller.id, action: "create", entity_type: "user",
      entity_id: created.user.id, detail: { email: created.user.email, role_id: body.role_id },
    });
    return jsonResponse(req, { id: created.user.id, email: created.user.email });
  } catch (err) {
    return errorResponse(req, err, "create-user", adminClient());
  }
});
