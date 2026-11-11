import { defineStore } from "pinia";
import { computed, ref, shallowRef } from "vue";
import type { Session } from "@supabase/supabase-js";
import { supabase, COOKIE_REFRESH_TOKEN } from "@/integrations/supabase/client";
import { resolvePermissions } from "@/lib/permissions";
import { logClientError } from "@/lib/errorLog";
import { browserLocale, setLocale } from "@/lib/i18n";
import { PROFILE_COLUMNS, type Action, type PermissionMap, type Profile } from "@/lib/types";

async function fetchAccess(userId: string) {
  const [profileRes, featuresRes, overridesRes] = await Promise.all([
    supabase.from("profiles").select(PROFILE_COLUMNS).eq("id", userId).maybeSingle(),
    supabase.from("m_features").select("*"),
    supabase.from("t_user_access_override").select("*").eq("user_id", userId),
  ]);
  const err = profileRes.error ?? featuresRes.error ?? overridesRes.error;
  if (err) throw err;
  const profile = profileRes.data as Profile | null;

  let rolePermissions: NonNullable<Awaited<ReturnType<typeof fetchRolePermissions>>> = [];
  if (profile?.role_id) rolePermissions = await fetchRolePermissions(profile.role_id);

  return {
    profile,
    permissions: resolvePermissions(featuresRes.data ?? [], rolePermissions, overridesRes.data ?? []),
  };
}

async function fetchRolePermissions(roleId: number) {
  const { data, error } = await supabase.from("t_role_permissions").select("*").eq("role_id", roleId);
  if (error) throw error;
  return data;
}

export const useAuthStore = defineStore("auth", () => {
  const session = shallowRef<Session | null>(null);
  const profile = ref<Profile | null>(null);
  const permissions = ref<PermissionMap>({});
  const ready = ref(false);

  const user = computed(() => session.value?.user ?? null);
  const isSuperadmin = computed(() => profile.value?.is_superadmin === true);
  const isAdmin = computed(() => profile.value?.role?.role_name === "Admin");
  const hasAccess = computed(
    () => profile.value?.role_id != null || Object.values(permissions.value).some((p) => p.can_read),
  );

  function can(feature: string, action: Action = "read") {
    return permissions.value[feature]?.[`can_${action}`] ?? false;
  }

  let generation = 0;
  let loadedUserId: string | null = null;

  async function loadAccess(userId: string) {
    const mine = ++generation;
    try {
      // ponytail: fixed 3 tries, 0.5s/1s backoff, enough for a transient blip.
      for (let attempt = 0; ; attempt++) {
        try {
          const result = await fetchAccess(userId);
          if (mine !== generation) return;
          loadedUserId = userId;
          profile.value = result.profile;
          permissions.value = result.permissions;
          setLocale(result.profile?.locale ?? browserLocale());
          break;
        } catch (err) {
          if (attempt >= 2) throw err;
          await new Promise((r) => setTimeout(r, 500 * (attempt + 1)));
          if (mine !== generation) return;
        }
      }
    } catch (err) {
      console.error("loadAccess failed:", err);
    } finally {
      if (mine === generation) ready.value = true;
    }
  }

  function init() {
    supabase.auth.onAuthStateChange((event, sess) => {
      if (event === "PASSWORD_RECOVERY" && window.location.pathname !== "/reset-password") {
        window.location.replace("/reset-password");
        return;
      }
      // Deferred because auth calls inside this callback deadlock.
      if (event === "INITIAL_SESSION" && !sess) {
        setTimeout(async () => {
          const { data } = await supabase.auth.refreshSession({ refresh_token: COOKIE_REFRESH_TOKEN });
          if (!data.session) ready.value = true;
        }, 0);
        return;
      }

      session.value = sess;
      if (sess?.user && loadedUserId === sess.user.id) {
        if (event === "USER_UPDATED") setTimeout(() => loadAccess(sess.user.id), 0);
      } else if (sess?.user) {
        ready.value = false;
        setTimeout(() => loadAccess(sess.user.id), 0);
      } else {
        generation++;
        loadedUserId = null;
        profile.value = null;
        permissions.value = {};
        ready.value = true;
      }
    });
  }

  async function signIn(email: string, password: string, captchaToken?: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password, options: { captchaToken } });
    if (error) {
      logClientError("auth.login", error.message, { email });
      throw error;
    }
  }

  async function signInWithGoogle(redirectPath = "/") {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${window.location.origin}${redirectPath}` },
    });
    if (error) throw error;
  }

  async function signOut() {
    await supabase.auth.signOut();
  }

  async function refreshProfile() {
    if (user.value) await loadAccess(user.value.id);
  }

  return {
    session, profile, permissions, ready, user, isSuperadmin, isAdmin, hasAccess,
    can, init, signIn, signInWithGoogle, signOut, refreshProfile,
  };
});
