import { z } from "npm:zod@4";
import { errorResponse, HttpError, jsonResponse, readJson, safeEqual } from "../_shared/cors.ts";
import { adminClient } from "../_shared/caller.ts";

const Body = z.object({
  email: z.email().max(254),
  password: z.string().regex(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,72}$/, "Password needs 8+ characters with upper case, lower case and a number"),
  full_name: z.string().trim().min(1).max(120),
});

Deno.serve(async (req) => {
  const admin = adminClient();
  try {
    const secret = Deno.env.get("SEED_ADMIN_SECRET");
    if (!secret) throw new HttpError(403, "Seeding is disabled");
    if (!safeEqual(req.headers.get("X-Seed-Secret"), secret)) throw new HttpError(403, "Invalid seed secret");

    const { count, error: countErr } = await admin
      .from("profiles")
      .select("id, role:m_roles!inner(role_name)", { count: "exact", head: true })
      .eq("role.role_name", "Admin");
    if (countErr) throw countErr;
    if ((count ?? 0) > 0) throw new HttpError(403, "An Admin account already exists");

    const parsed = Body.safeParse(await readJson(req));
    if (!parsed.success) throw new HttpError(400, parsed.error.issues[0]?.message ?? "Invalid body");
    const { email, password, full_name } = parsed.data;

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name },
    });
    if (createErr) throw new HttpError(400, createErr.message);

    const { error: updateErr } = await admin.from("profiles").update({ full_name, role_id: 1 }).eq("id", created.user.id);
    if (updateErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      throw updateErr;
    }
    await admin.from("t_audit_log").insert({
      actor_id: null, action: "create", entity_type: "user", entity_id: created.user.id,
      detail: { email, role_id: 1, via: "seed-admin" },
    });
    return jsonResponse(null, { id: created.user.id, email: created.user.email });
  } catch (err) {
    return errorResponse(null, err, "seed-admin", admin);
  }
});
