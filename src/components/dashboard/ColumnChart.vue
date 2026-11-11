<script setup lang="ts">
import { computed } from "vue";

export interface ColumnSeries {
  label: string;
  values: number[];
  tone: string;
}

const props = defineProps<{ labels: string[]; series: ColumnSeries[]; line?: ColumnSeries; format?: (n: number) => string }>();
const W = 640;
const H = 220;
const PAD = { top: 12, right: 8, bottom: 22, left: 48 };
const compact = new Intl.NumberFormat("id-ID", { notation: "compact", maximumFractionDigits: 1 });
const fmt = (n: number) => (props.format ?? ((v: number) => v.toLocaleString("id-ID")))(n);

const all = computed(() => [...props.series.flatMap((s) => s.values), ...(props.line?.values ?? [])]);
const max = computed(() => Math.max(1, ...all.value));
const min = computed(() => Math.min(0, ...all.value));
const y = (v: number) => PAD.top + ((max.value - v) / (max.value - min.value)) * (H - PAD.top - PAD.bottom);
const slot = computed(() => (W - PAD.left - PAD.right) / Math.max(1, props.labels.length));
const barW = computed(() => Math.min(18, (slot.value * 0.7) / Math.max(1, props.series.length)));
const cx = (i: number) => PAD.left + slot.value * (i + 0.5);
const bars = computed(() =>
  props.labels.flatMap((_, i) =>
    props.series.map((s, k) => {
      const v = s.values[i] ?? 0;
      const x = cx(i) - (barW.value * props.series.length) / 2 + k * barW.value + 1;
      return { key: `${i}-${k}`, x, y: Math.min(y(v), y(0)), h: Math.max(1, Math.abs(y(v) - y(0))), w: barW.value - 2, tone: s.tone };
    }),
  ),
);
const linePath = computed(() => props.line?.values.map((v, i) => `${i ? "L" : "M"}${cx(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" ") ?? "");
const ticks = computed(() => [...new Set([max.value, max.value / 2, 0, min.value])].filter((v, i, a) => i === 0 || v < a[i - 1]));
const tip = (i: number) =>
  [props.labels[i], ...props.series.map((s) => `${s.label}: ${fmt(s.values[i] ?? 0)}`), props.line && `${props.line.label}: ${fmt(props.line.values[i] ?? 0)}`]
    .filter(Boolean)
    .join("\n");
</script>

<template>
  <div class="space-y-2">
    <div class="text-muted-foreground flex flex-wrap gap-x-4 gap-y-1 text-xs">
      <span v-for="s in series" :key="s.label" class="flex items-center gap-1.5"><svg class="size-2.5" aria-hidden="true"><rect width="10" height="10" rx="2" :class="s.tone" /></svg>{{ s.label }}</span>
      <span v-if="line" class="flex items-center gap-1.5"><svg class="h-2.5 w-4" aria-hidden="true"><line x1="0" x2="16" y1="5" y2="5" :class="line.tone" stroke-width="2" /></svg>{{ line.label }}</span>
    </div>
    <svg :viewBox="`0 0 ${W} ${H}`" class="block h-auto w-full" role="img" :aria-label="series.map((s) => s.label).join(', ')">
      <g v-for="t in ticks" :key="t" class="text-muted-foreground">
        <line :x1="PAD.left" :x2="W - PAD.right" :y1="y(t)" :y2="y(t)" :class="t === 0 ? 'stroke-border' : 'stroke-border/60'" :stroke-dasharray="t === 0 ? undefined : '3 4'" />
        <text :x="PAD.left - 8" :y="y(t) + 4" text-anchor="end" font-size="10" fill="currentColor">{{ compact.format(t) }}</text>
      </g>
      <rect v-for="b in bars" :key="b.key" :x="b.x" :y="b.y" :width="b.w" :height="b.h" rx="2" :class="b.tone" />
      <template v-if="line">
        <path :d="linePath" fill="none" :class="line.tone" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" />
        <circle v-for="(v, i) in line.values" :key="i" :cx="cx(i)" :cy="y(v)" r="3" :class="['fill-card', line.tone]" stroke-width="2" />
      </template>
      <g v-for="(l, i) in labels" :key="i" class="text-muted-foreground">
        <text :x="cx(i)" :y="H - 6" text-anchor="middle" font-size="10" fill="currentColor">{{ l }}</text>
        <rect :x="cx(i) - slot / 2" :y="0" :width="slot" :height="H" fill="transparent" class="hover:fill-current/5"><title>{{ tip(i) }}</title></rect>
      </g>
    </svg>
  </div>
</template>
