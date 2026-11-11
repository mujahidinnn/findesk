<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { Clock, LogOut, RefreshCw } from "@lucide/vue";
import { Button } from "@/components/ui/button";
import { useAuthStore } from "@/stores/auth";
import { router } from "@/router";

const { t } = useI18n();
const auth = useAuthStore();

async function check() {
  await auth.refreshProfile();
  if (auth.hasAccess) router.replace("/");
}

async function signOut() {
  await auth.signOut();
  router.replace("/login");
}
</script>

<template>
  <div class="flex min-h-full items-center justify-center p-6">
    <div class="max-w-sm text-center">
      <Clock class="text-primary-text mx-auto size-10" />
      <h1 class="mt-4 text-xl font-semibold">{{ t("pending.title") }}</h1>
      <p class="text-muted-foreground mt-2 text-sm">{{ t("pending.body", { email: auth.user?.email }) }}</p>
      <div class="mt-6 flex justify-center gap-2">
        <Button variant="outline" @click="check"><RefreshCw /> {{ t("pending.check") }}</Button>
        <Button variant="ghost" @click="signOut"><LogOut /> {{ t("shell.signOut") }}</Button>
      </div>
    </div>
  </div>
</template>
