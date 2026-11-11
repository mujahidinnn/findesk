<script setup lang="ts">
import { CircleAlert, CircleCheck } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { formatAmount } from "@/lib/format";
import { isZero } from "@/lib/statements";

defineProps<{ label: string; diff: number }>();
const { t } = useI18n();
</script>

<template>
  <div
    role="status"
    :class="[
      'mt-4 flex flex-wrap items-center gap-2 rounded-lg border border-dashed px-3 py-2 text-sm',
      isZero(diff) ? 'text-success border-green-500/40' : 'border-rose-400 bg-rose-500/5 text-rose-700 dark:text-rose-400',
    ]"
  >
    <component :is="isZero(diff) ? CircleCheck : CircleAlert" class="size-4 shrink-0" />
    <span class="font-medium">{{ label }}</span>
    <span class="ml-auto tabular-nums">{{ isZero(diff) ? t("reports.balanced") : t("reports.difference", { amount: formatAmount(diff) }) }}</span>
  </div>
</template>
