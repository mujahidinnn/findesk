<script setup lang="ts">
import { computed, ref, watchEffect } from "vue";
import { useI18n } from "vue-i18n";
import { useQuery } from "@tanstack/vue-query";
import { useRoute, useRouter } from "vue-router";
import { ArrowLeft, LogIn, Mail } from "@lucide/vue";
import PasswordInput from "@/components/common/PasswordInput.vue";
import AuthLayout from "@/components/auth/AuthLayout.vue";
import TurnstileWidget, { captchaRequired } from "@/components/auth/TurnstileWidget.vue";
import GoogleIcon from "@/components/brand/GoogleIcon.vue";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { useAuthStore } from "@/stores/auth";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const email = ref("");
const password = ref("");
const error = ref<string | null>(null);
const info = ref<string | null>(null);
const busy = ref<"password" | "google" | "reset" | null>(null);
const forgot = computed(() => route.query.mode === "forgot");
const captcha = ref("");
const captchaWidget = ref<InstanceType<typeof TurnstileWidget>>();
const captchaMissing = computed(() => captchaRequired && !captcha.value);

const target = computed(() => {
  const r = route.query.redirect;
  return typeof r === "string" && r.startsWith("/") && !r.startsWith("//") ? r : "/";
});
watchEffect(() => {
  if (!auth.ready || !auth.user) return;
  router.replace(target.value);
});

function message(err: unknown) {
  const msg = err instanceof Error ? err.message.toLowerCase() : "";
  if (msg.includes("captcha")) return t("login.errors.captcha");
  if (msg.includes("invalid") || msg.includes("credentials")) return t("login.errors.invalidCredentials");
  if (msg.includes("provider is not enabled") || msg.includes("unsupported provider")) return t("login.errors.googleNotConfigured");
  return t("login.errors.generic");
}

async function run(kind: NonNullable<typeof busy.value>, fn: () => Promise<void>) {
  error.value = info.value = null;
  busy.value = kind;
  try {
    await fn();
  } catch (err) {
    error.value = message(err);
  } finally {
    busy.value = null;
    captchaWidget.value?.reset();
  }
}

const demoMode = useQuery({
  queryKey: ["public-demo-mode"],
  queryFn: async () => (await supabase.rpc("public_demo_mode")).data === true,
});
const DEMO_PASSWORD = "Demo12345";
const DEMO_ACCOUNTS = [
  { email: "manager@findesk.demo", role: "Finance Manager" },
  { email: "accountant@findesk.demo", role: "Accountant" },
  { email: "staff@findesk.demo", role: "Finance Staff" },
  { email: "auditor@findesk.demo", role: "Auditor" },
  { email: "employee@findesk.demo", role: "Employee" },
];
function pickDemo(demoEmail: string) {
  error.value = null;
  email.value = demoEmail;
  password.value = DEMO_PASSWORD;
}

const signIn = () => run("password", () => auth.signIn(email.value, password.value, captcha.value || undefined));
const google = () => run("google", auth.signInWithGoogle);
const sendReset = () =>
  run("reset", async () => {
    const { error: e } = await supabase.auth.resetPasswordForEmail(email.value, {
      redirectTo: `${window.location.origin}/reset-password`,
      captchaToken: captcha.value || undefined,
    });
    if (e) throw e;
    info.value = t("login.resetSent");
  });
</script>

<template>
  <AuthLayout>
    <template v-if="forgot">
      <h1 class="text-2xl font-semibold tracking-tight">{{ t("login.forgotTitle") }}</h1>
      <p class="text-muted-foreground mt-1 text-sm">{{ t("login.forgotHint") }}</p>
      <form class="mt-8 space-y-4" @submit.prevent="sendReset">
        <div class="space-y-1.5">
          <Label for="email">{{ t("login.email") }}</Label>
          <Input id="email" v-model="email" type="email" autocomplete="email" required autofocus />
        </div>
        <TurnstileWidget ref="captchaWidget" v-model="captcha" />
        <p v-if="info" role="status" class="rounded-lg bg-emerald-500/10 px-3 py-2 text-xs text-emerald-700 dark:text-emerald-400">{{ info }}</p>
        <p v-if="error" role="alert" class="rounded-lg bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-400">{{ error }}</p>
        <Button type="submit" class="h-10 w-full" :disabled="!email || captchaMissing || busy !== null" :loading="busy === 'reset'"><Mail /> {{ t("login.sendReset") }}</Button>
        <Button type="button" variant="link" class="w-full" @click="router.replace({ query: {} })"><ArrowLeft /> {{ t("login.backToSignIn") }}</Button>
      </form>
    </template>

    <template v-else>
      <h1 class="text-2xl font-semibold tracking-tight">{{ t("login.welcome") }}</h1>
      <p class="text-muted-foreground mt-1 text-sm">{{ t("login.subtitle") }}</p>
      <form class="mt-8 space-y-4" @submit.prevent="signIn">
        <div class="space-y-1.5">
          <Label for="email">{{ t("login.email") }}</Label>
          <Input id="email" v-model="email" type="email" autocomplete="username" required autofocus class="h-10" />
        </div>
        <div class="space-y-1.5">
          <Label for="password">{{ t("login.password") }}</Label>
          <PasswordInput id="password" v-model="password" autocomplete="current-password" required class="h-10" />
        </div>
        <div class="flex justify-end">
          <RouterLink :to="{ query: { mode: 'forgot' } }" class="text-primary-text text-xs font-semibold hover:underline">
            {{ t("login.forgotPassword") }}
          </RouterLink>
        </div>
        <TurnstileWidget ref="captchaWidget" v-model="captcha" />
        <p v-if="error" role="alert" class="rounded-lg bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-400">{{ error }}</p>
        <Button type="submit" class="h-10 w-full font-semibold" :disabled="!email || !password || captchaMissing || busy !== null" :loading="busy === 'password'">
          <LogIn /> {{ busy === "password" ? t("login.signingIn") : t("login.signIn") }}
        </Button>
        <Button type="button" variant="outline" class="h-10 w-full gap-2" :disabled="busy !== null" :loading="busy === 'google'" @click="google">
          <GoogleIcon v-if="busy !== 'google'" />
          {{ busy === "google" ? t("login.redirecting") : t("login.continueWithGoogle") }}
        </Button>
      </form>

      <div v-if="demoMode.data.value" class="mt-4">
        <p class="text-muted-foreground mb-1.5 text-[11px] font-semibold tracking-wide uppercase">{{ t("login.demoTitle") }}</p>
        <div class="grid grid-cols-2 gap-1.5">
          <button
            v-for="a in DEMO_ACCOUNTS"
            :key="a.email"
            type="button"
            class="hover:bg-muted rounded-md border px-2 py-0.5 text-left transition-colors"
            @click="pickDemo(a.email)"
          >
            <span class="text-foreground block text-xs leading-tight font-semibold">{{ a.role }}</span>
            <span class="text-muted-foreground block truncate text-[11px] leading-tight">{{ a.email }}</span>
          </button>
        </div>
        <p class="text-muted-foreground mt-2 text-xs">
          {{ t("login.demoPassword") }}
          <code class="bg-muted text-foreground rounded px-1.5 py-0.5 font-mono text-[11px] font-semibold select-all">{{ DEMO_PASSWORD }}</code>
        </p>
      </div>
    </template>
  </AuthLayout>
</template>
