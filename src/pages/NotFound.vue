<script setup lang="ts">
import { ArrowLeft } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { Button } from "@/components/ui/button";

const { t } = useI18n();
</script>

<template>
  <div class="flex min-h-full flex-col items-center justify-center p-6 text-center">
    <p class="text-primary-text font-mono text-5xl font-bold">404</p>
    <h1 class="mt-3 text-xl font-semibold">{{ t("notFound.title") }}</h1>
    <p class="text-muted-foreground mt-1 text-sm">{{ t("notFound.body") }}</p>
    <Button as-child variant="outline" class="mt-6"><RouterLink to="/"><ArrowLeft /> {{ t("common.backHome") }}</RouterLink></Button>
  </div>
</template>
