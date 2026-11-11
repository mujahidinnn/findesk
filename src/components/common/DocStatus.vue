<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import StatusBadge, { type Tone } from "@/components/common/StatusBadge.vue";

const props = defineProps<{ status: string; paid?: unknown; total?: unknown; due?: string | null }>();
const { t } = useI18n();

const TONES: Record<string, Tone> = {
  draft: "muted", submitted: "warning", posted: "info", paid: "success", partial: "warning", void: "danger", reversed: "muted",
  approved: "info", open: "info", closed: "muted", finished: "success", active: "success", disposed: "muted", overdue: "danger",
};
const key = computed(() => {
  if (props.status !== "posted" || props.total == null) return props.status;
  if (Number(props.paid ?? 0) > 0) return "partial";
  const today = new Date().toISOString().slice(0, 10);
  return props.due && props.due < today ? "overdue" : "posted";
});
</script>

<template>
  <StatusBadge :tone="TONES[key] ?? 'muted'">{{ t(`status.${key}`) }}</StatusBadge>
</template>
