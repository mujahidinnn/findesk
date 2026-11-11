<script setup lang="ts">
import { Camera, KeyRound, KeySquare, Mail, Save, ShieldCheck } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useColorMode } from "@vueuse/core";
import { toast } from "vue-sonner";
import PasswordInput from "@/components/common/PasswordInput.vue";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { supabase } from "@/integrations/supabase/client";
import { SUPPORTED_LOCALES, setLocale, type Locale } from "@/lib/i18n";
import { useAuthStore } from "@/stores/auth";
import { useServerError } from "@/composables/useServerError";

const { t, locale } = useI18n();
const auth = useAuthStore();
const { store: themePref } = useColorMode();

const fullName = ref("");
const lang = ref<Locale>(locale.value as Locale);
const password = ref("");
const password2 = ref("");
const code = ref("");
const codeSent = ref(false);
const newEmail = ref("");
const busy = ref<"profile" | "password" | "avatar" | "email" | null>(null);
const serverError = useServerError();
const STRONG = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,72}$/;

watch(
  () => auth.profile,
  (p) => {
    fullName.value = p?.full_name ?? "";
    if (p?.locale) lang.value = p.locale;
  },
  { immediate: true },
);

async function saveProfile() {
  if (!auth.user || !fullName.value.trim()) return;
  busy.value = "profile";
  const { error } = await supabase
    .from("profiles")
    .update({ full_name: fullName.value.trim().slice(0, 120), locale: lang.value })
    .eq("id", auth.user.id);
  busy.value = null;
  if (error) return toast.error(t("common.saveFailed"));
  setLocale(lang.value);
  await auth.refreshProfile();
  toast.success(t("common.saved"));
}

// Two steps: the new password is checked, then a code is emailed (reauthenticate) that must come back with the change,
// so a left-open session cannot change the password, and a forgotten current password is no obstacle.
async function sendCode() {
  if (auth.user?.email?.endsWith("@findesk.demo")) return toast.error(t("password.demoLocked"));
  if (!STRONG.test(password.value)) return toast.error(t("password.weak"));
  if (password.value !== password2.value) return toast.error(t("password.mismatch"));
  busy.value = "password";
  const { error } = await supabase.auth.reauthenticate();
  busy.value = null;
  if (error) return toast.error(serverError(error));
  codeSent.value = true;
  toast.success(t("password.codeSent", { email: auth.user?.email ?? "" }));
}
async function savePassword() {
  if (!codeSent.value) return sendCode();
  busy.value = "password";
  const { error } = await supabase.auth.updateUser({ password: password.value, nonce: code.value.trim() });
  if (error) {
    busy.value = null;
    return toast.error(t("password.codeInvalid"));
  }
  await supabase.auth.signOut({ scope: "others" });
  busy.value = null;
  password.value = password2.value = code.value = "";
  codeSent.value = false;
  toast.success(t("password.changed"));
}
async function saveEmail() {
  if (auth.user?.email?.endsWith("@findesk.demo")) return toast.error(t("email.demoLocked"));
  const email = newEmail.value.trim().toLowerCase();
  if (!email || email === auth.user?.email) return;
  busy.value = "email";
  const { error } = await supabase.auth.updateUser({ email }, { emailRedirectTo: `${window.location.origin}/settings/profile` });
  busy.value = null;
  if (error) return toast.error(error.message);
  newEmail.value = "";
  toast.success(t("email.sent", { email }));
}
async function uploadAvatar(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0];
  if (!file || !auth.user) return;
  busy.value = "avatar";
  try {
    const path = `${auth.user.id}/${Date.now()}.${file.name.split(".").pop()?.toLowerCase() || "png"}`;
    const up = await supabase.storage.from("avatars").upload(path, file, { contentType: file.type });
    if (up.error) throw up.error;
    const url = supabase.storage.from("avatars").getPublicUrl(path).data.publicUrl;
    const { error } = await supabase.from("profiles").update({ avatar_url: url }).eq("id", auth.user.id);
    if (error) throw error;
    await auth.refreshProfile();
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    busy.value = null;
  }
}

const initials = computed(() => (auth.profile?.full_name ?? "?").split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase());
const fmtDate = (iso: string | null | undefined, time = false) =>
  iso ? new Date(iso).toLocaleString("id-ID", time ? { dateStyle: "medium", timeStyle: "short" } : { dateStyle: "medium" }) : "-";
const featureName = (key: string) => t(`features.${key}`);
const access = computed(() =>
  Object.entries(auth.permissions)
    .filter(([, p]) => p.can_read)
    .map(([key, p]) => ({ key, name: featureName(key), crud: [["C", p.can_create], ["R", p.can_read], ["U", p.can_update], ["D", p.can_delete]] as const }))
    .sort((a, b) => a.name.localeCompare(b.name, locale.value)),
);
</script>

<template>
  <div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
    <div class="space-y-6">
      <form class="bg-card space-y-4 rounded-xl border p-5" @submit.prevent="saveProfile">
        <h2 class="font-semibold">{{ t("profile.account") }}</h2>
        <div class="space-y-1.5">
          <Label for="email">{{ t("login.email") }}</Label>
          <Input id="email" :model-value="auth.user?.email" disabled />
        </div>
        <div class="space-y-1.5">
          <Label for="name">{{ t("profile.fullName") }}</Label>
          <Input id="name" v-model="fullName" maxlength="120" required />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-1.5">
            <Label for="lang">{{ t("profile.language") }}</Label>
            <Select v-model="lang">
              <SelectTrigger id="lang" class="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem v-for="l in SUPPORTED_LOCALES" :key="l.code" :value="l.code">{{ l.label }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div class="space-y-1.5">
            <Label for="theme">{{ t("shell.theme") }}</Label>
            <Select v-model="themePref">
              <SelectTrigger id="theme" class="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="light">{{ t("shell.themeLight") }}</SelectItem>
                <SelectItem value="dark">{{ t("shell.themeDark") }}</SelectItem>
                <SelectItem value="auto">{{ t("shell.themeSystem") }}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <Button type="submit" :disabled="busy !== null" :loading="busy === 'profile'"><Save /> {{ t("common.save") }}</Button>
      </form>

      <form class="bg-card space-y-4 rounded-xl border p-5" @submit.prevent="saveEmail">
        <h2 class="font-semibold">{{ t("email.changeTitle") }}</h2>
        <p class="text-muted-foreground text-xs">{{ t("email.rule") }}</p>
        <div class="space-y-1.5">
          <Label for="new-email">{{ t("email.new") }}</Label>
          <Input id="new-email" v-model="newEmail" type="email" autocomplete="email" required />
        </div>
        <Button type="submit" variant="outline" :disabled="busy !== null || !newEmail" :loading="busy === 'email'"><Mail /> {{ t("email.change") }}</Button>
      </form>

      <form class="bg-card space-y-4 rounded-xl border p-5" @submit.prevent="savePassword">
        <h2 class="font-semibold">{{ t("password.changeTitle") }}</h2>
        <p class="text-muted-foreground text-xs">{{ t("password.rule") }}</p>
        <div class="space-y-1.5">
          <Label for="new-password">{{ t("password.new") }}</Label>
          <PasswordInput id="new-password" v-model="password" autocomplete="new-password" required :disabled="codeSent" />
        </div>
        <div class="space-y-1.5">
          <Label for="new-password2">{{ t("password.confirm") }}</Label>
          <PasswordInput id="new-password2" v-model="password2" autocomplete="new-password" required :disabled="codeSent" />
        </div>
        <div v-if="codeSent" class="space-y-1.5">
          <Label for="password-code">{{ t("password.code") }}</Label>
          <Input id="password-code" v-model="code" inputmode="numeric" autocomplete="one-time-code" maxlength="8" class="font-mono tracking-[0.3em]" required autofocus />
          <p class="text-muted-foreground text-xs">
            {{ t("password.codeHint", { email: auth.user?.email ?? "" }) }}
            <button type="button" class="text-primary-text font-medium hover:underline" :disabled="busy !== null" @click="sendCode">{{ t("password.resend") }}</button>
          </p>
        </div>
        <Button type="submit" variant="outline" :disabled="busy !== null || !password || !password2 || (codeSent && !code.trim())" :loading="busy === 'password'">
          <KeyRound /> {{ codeSent ? t("password.change") : t("password.sendCode") }}
        </Button>
      </form>
    </div>

    <aside class="space-y-4">
      <section class="bg-card overflow-hidden rounded-xl border">
        <div class="bg-primary-soft h-16" />
        <div class="-mt-8 px-5 pb-5">
          <label class="group relative block size-16 cursor-pointer" :title="t('profile.changeAvatar')">
            <img v-if="auth.profile?.avatar_url" :src="auth.profile.avatar_url" alt="" class="border-card size-16 rounded-xl border-4 object-cover" />
            <span v-else class="bg-brand-100 text-brand-800 dark:bg-brand-900 dark:text-brand-200 border-card flex size-16 items-center justify-center rounded-xl border-4 text-lg font-bold">{{ initials }}</span>
            <span class="absolute inset-1 flex items-center justify-center rounded-xl bg-black/40 text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">
              <Camera class="size-5" :class="busy === 'avatar' && 'animate-pulse'" />
            </span>
            <input type="file" accept="image/png,image/jpeg,image/webp" class="sr-only" :aria-label="t('profile.changeAvatar')" :disabled="busy !== null" @change="uploadAvatar" />
          </label>
          <p class="mt-2 text-lg font-semibold tracking-tight">{{ auth.profile?.full_name }}</p>
          <p class="text-muted-foreground truncate text-xs">{{ auth.user?.email }}</p>
          <div class="mt-3 flex flex-wrap gap-1.5">
            <span class="text-primary-text flex items-center gap-1 rounded-md border border-brand-200 bg-brand-50 px-2 py-0.5 text-[11px] font-semibold dark:bg-brand-500/10">
              <ShieldCheck class="size-3" /> {{ auth.isSuperadmin ? "Superadmin" : (auth.profile?.role?.role_name ?? "-") }}
            </span>
            <span v-if="auth.profile?.employee_code" class="bg-secondary rounded-md px-2 py-0.5 font-mono text-[11px]">{{ auth.profile.employee_code }}</span>
          </div>
          <dl class="mt-4 space-y-2 text-xs">
            <div class="flex justify-between gap-3"><dt class="text-muted-foreground">{{ t("profile.memberSince") }}</dt><dd class="font-medium">{{ fmtDate(auth.user?.created_at) }}</dd></div>
            <div class="flex justify-between gap-3"><dt class="text-muted-foreground">{{ t("profile.lastSignIn") }}</dt><dd class="font-medium">{{ fmtDate(auth.user?.last_sign_in_at, true) }}</dd></div>
          </dl>
        </div>
      </section>

      <section class="bg-card rounded-xl border p-5">
        <h2 class="flex items-center gap-2 text-sm font-semibold"><KeySquare class="text-muted-foreground size-4" /> {{ t("profile.access", { n: access.length }) }}</h2>
        <p class="text-muted-foreground mt-1 text-xs">{{ t("settings.matrix.legend") }}</p>
        <ul class="mt-3 divide-y text-sm">
          <li v-for="a in access" :key="a.key" class="flex items-center gap-2 py-2 first:pt-0 last:pb-0">
            <span class="min-w-0 flex-1 truncate">{{ a.name }}</span>
            <span class="inline-flex shrink-0 gap-0.5 font-mono text-[11px]" :aria-label="a.crud.filter(([, on]) => on).map(([l]) => l).join('')">
              <span v-for="[l, on] in a.crud" :key="l" :class="['w-3.5 text-center rounded-sm', on ? 'bg-primary-soft text-primary-text font-semibold' : 'text-muted-foreground/30']" aria-hidden="true">{{ l }}</span>
            </span>
          </li>
        </ul>
      </section>
    </aside>
  </div>
</template>
