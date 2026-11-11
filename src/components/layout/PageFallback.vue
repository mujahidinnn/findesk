<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { RefreshCw, TriangleAlert } from "@lucide/vue";
import { Button } from "@/components/ui/button";

defineEmits<{ retry: [] }>();
const { t } = useI18n();
</script>

<template>
  <div role="alert" class="flex flex-col items-center justify-center py-20 text-center">
    <TriangleAlert class="text-destructive size-8" />
    <p class="mt-3 font-medium">{{ t("errors.pageTitle") }}</p>
    <p class="text-muted-foreground mt-1 text-sm">{{ t("errors.pageBody") }}</p>
    <Button class="mt-4" variant="outline" @click="$emit('retry')"><RefreshCw /> {{ t("common.retry") }}</Button>
  </div>
</template>
