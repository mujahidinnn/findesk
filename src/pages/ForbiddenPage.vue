<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { ArrowLeft, ShieldX } from "@lucide/vue";
import { Button } from "@/components/ui/button";

const { t } = useI18n();
</script>

<template>
  <div class="flex min-h-full flex-col items-center justify-center p-6 text-center">
    <ShieldX class="text-destructive size-10" />
    <h1 class="mt-4 text-xl font-semibold">{{ t("forbidden.title") }}</h1>
    <p class="text-muted-foreground mt-1 max-w-sm text-sm">{{ t("forbidden.body") }}</p>
    <Button as-child variant="outline" class="mt-6"><RouterLink to="/"><ArrowLeft /> {{ t("common.backHome") }}</RouterLink></Button>
  </div>
</template>
