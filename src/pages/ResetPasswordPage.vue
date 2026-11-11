<script setup lang="ts">
import { Save } from "@lucide/vue";
import { onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute, useRouter } from "vue-router";
import { toast } from "vue-sonner";
import PasswordInput from "@/components/common/PasswordInput.vue";
import AuthLayout from "@/components/auth/AuthLayout.vue";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { useAuthStore } from "@/stores/auth";

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const auth = useAuthStore();
const password = ref("");
const confirm = ref("");
const error = ref<string | null>(null);
const busy = ref(false);

// The reset mail links to our own domain with a token_hash (a link to *.supabase.co from our sender
// looks like phishing); trade it for a session here. Older fragment links still sign in on their own.
const verifying = ref(typeof route.query.token_hash === "string");
onMounted(async () => {
  if (!verifying.value) return;
  await supabase.auth.verifyOtp({ token_hash: route.query.token_hash as string, type: "recovery" });
  verifying.value = false;
  router.replace({ query: {} });
});

const STRONG = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,72}$/;

async function save() {
  error.value = null;
  if (!STRONG.test(password.value)) return (error.value = t("password.weak"));
  if (password.value !== confirm.value) return (error.value = t("password.mismatch"));
  busy.value = true;
  const { error: e } = await supabase.auth.updateUser({ password: password.value });
  busy.value = false;
  if (e) return (error.value = e.message);
  toast.success(t("password.changed"));
  router.replace("/");
}
</script>

<template>
  <AuthLayout>
    <h1 class="text-2xl font-semibold tracking-tight">{{ t("password.resetTitle") }}</h1>
    <p v-if="verifying" class="text-muted-foreground mt-2 text-sm">{{ t("common.loading") }}</p>
    <p v-else-if="auth.ready && !auth.user" class="text-muted-foreground mt-2 text-sm">
      {{ t("password.linkExpired") }}
      <RouterLink to="/login?mode=forgot" class="text-primary-text font-semibold hover:underline">{{ t("login.sendReset") }}</RouterLink>
    </p>
    <form v-else class="mt-8 space-y-4" @submit.prevent="save">
      <p class="text-muted-foreground text-xs">{{ t("password.rule") }}</p>
      <div class="space-y-1.5">
        <Label for="new">{{ t("password.new") }}</Label>
        <PasswordInput id="new" v-model="password" autocomplete="new-password" required />
      </div>
      <div class="space-y-1.5">
        <Label for="confirm">{{ t("password.confirm") }}</Label>
        <PasswordInput id="confirm" v-model="confirm" autocomplete="new-password" required />
      </div>
      <p v-if="error" role="alert" class="rounded-lg bg-rose-500/10 px-3 py-2 text-xs text-rose-700 dark:text-rose-400">{{ error }}</p>
      <Button type="submit" class="h-10 w-full" :disabled="busy" :loading="busy"><Save /> {{ t("common.save") }}</Button>
    </form>
  </AuthLayout>
</template>
