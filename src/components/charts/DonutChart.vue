<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";

export interface Slice {
  label: string;
  value: number;
  href?: string;
}

const props = defineProps<{ rows: Slice[]; format?: (n: number) => string }>();
const { t } = useI18n();
const fmt = (n: number) => (props.format ?? ((v: number) => v.toLocaleString("id-ID")))(n);
const slices = computed(() => {
  const sorted = [...props.rows].filter((r) => r.value > 0).sort((a, b) => b.value - a.value);
  const head = sorted.slice(0, 4);
  const rest = sorted.slice(4).reduce((s, r) => s + r.value, 0);
  return rest > 0 ? [...head, { label: t("common.other"), value: rest } as Slice] : head;
});
const total = computed(() => slices.value.reduce((s, r) => s + r.value, 0));
const arcs = computed(() => {
  let start = 0;
  return slices.value.map((s, i) => {
    const share = (s.value / total.value) * 100;
    const arc = { ...s, i, share, start, color: `var(--chart-cat-${i + 1})` };
    start += share;
    return arc;
  });
});
</script>

<template>
  <div class="flex flex-col items-center gap-6">
    <svg viewBox="0 0 120 120" class="size-44 shrink-0" role="img">
      <circle
        v-for="a in arcs"
        :key="a.label"
        cx="60"
        cy="60"
        r="48"
        fill="none"
        :stroke="a.color"
        stroke-width="16"
        pathLength="100"
        :stroke-dasharray="`${Math.max(0, a.share - 1.2)} ${100 - Math.max(0, a.share - 1.2)}`"
        :stroke-dashoffset="-a.start - 0.6"
        transform="rotate(-90 60 60)"
        class="transition-opacity hover:opacity-80"
      >
        <title>{{ a.label }}: {{ fmt(a.value) }} ({{ a.share.toFixed(0) }}%)</title>
      </circle>
      <text x="60" y="58" text-anchor="middle" font-size="9" class="text-muted-foreground" fill="currentColor">{{ t("common.total") }}</text>
      <text x="60" y="72" text-anchor="middle" font-size="11" font-weight="600" fill="currentColor">{{ fmt(total) }}</text>
    </svg>
    <ul class="w-full min-w-0 space-y-2 text-sm">
      <li v-for="a in arcs" :key="a.label" class="flex items-center gap-2">
        <span class="inline-block size-2.5 shrink-0 rounded-xs" :style="{ background: a.color }" />
        <RouterLink v-if="a.href" :to="a.href" class="truncate hover:underline">{{ a.label }}</RouterLink>
        <span v-else class="truncate">{{ a.label }}</span>
        <span class="text-muted-foreground ml-auto shrink-0 text-xs tabular-nums">{{ a.share.toFixed(0) }}%</span>
        <span class="w-24 shrink-0 text-right text-xs tabular-nums">{{ fmt(a.value) }}</span>
      </li>
    </ul>
  </div>
</template>
