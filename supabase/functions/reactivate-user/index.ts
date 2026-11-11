import { z } from "npm:zod@4";
import { corsHeaders, errorResponse, HttpError, jsonResponse, readJson } from "../_shared/cors.ts";
import { adminClient, requireCaller, requireTargetBelow } from "../_shared/caller.ts";

const Body = z.object({ user_id: z.uuid() });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    const caller = await requireCaller(req, "users", "update");
    const parsed = Body.safeParse(await readJson(req));
    if (!parsed.success) throw new HttpError(400, "user_id is required");
    const { user_id } = parsed.data;
    await requireTargetBelow(caller, user_id);

    const { error } = await caller.admin.auth.admin.updateUserById(user_id, { ban_duration: "none" });
    if (error) throw new HttpError(400, error.message);

    await caller.admin.from("t_audit_log").insert({
      actor_id: caller.id, action: "update", entity_type: "user", entity_id: user_id, detail: { banned: false },
    });
    return jsonResponse(req, { success: true });
  } catch (err) {
    return errorResponse(req, err, "reactivate-user", adminClient());
  }
});
