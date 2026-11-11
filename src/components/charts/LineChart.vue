<script setup lang="ts">
import { computed } from "vue";

export interface TrendPoint {
  date: string;
  value: number;
}

const props = withDefaults(defineProps<{ points: TrendPoint[]; format?: (n: number) => string; zeroBased?: boolean }>(), { zeroBased: true, format: undefined });
const W = 1200;
const H = 200;
const PAD = { top: 24, right: 16, bottom: 8, left: props.zeroBased ? 44 : 64 };
const compact = new Intl.NumberFormat("id-ID", { notation: "compact", maximumFractionDigits: 1 });
const fmt = (n: number) => (props.format ?? ((v: number) => v.toLocaleString("id-ID")))(n);
const day = (iso: string) => new Date(`${iso}T00:00`).toLocaleDateString("id-ID", { day: "numeric", month: "short" });

const max = computed(() => Math.max(1, ...props.points.map((p) => p.value)));
const lo = computed(() => {
  if (props.zeroBased || !props.points.length) return 0;
  const vals = props.points.map((p) => p.value);
  const min = Math.min(...vals), top = Math.max(...vals);
  return min - ((top - min) || Math.abs(top) * 0.01 || 1) * 0.1;
});
const hi = computed(() => (props.zeroBased ? max.value : Math.max(...props.points.map((p) => p.value)) + (max.value - lo.value) * 0.1));
const x = (i: number) => PAD.left + (props.points.length > 1 ? (i / (props.points.length - 1)) * (W - PAD.left - PAD.right) : 0);
const y = (v: number) => PAD.top + (1 - (v - lo.value) / (hi.value - lo.value)) * (H - PAD.top - PAD.bottom);
const coords = computed(() => props.points.map((p, i) => ({ ...p, x: x(i), y: y(p.value) })));
const line = computed(() => coords.value.map((c, i) => `${i ? "L" : "M"}${c.x.toFixed(1)} ${c.y.toFixed(1)}`).join(" "));
const area = computed(() =>
  coords.value.length ? `${line.value} L${coords.value[coords.value.length - 1].x.toFixed(1)} ${y(lo.value)} L${coords.value[0].x.toFixed(1)} ${y(lo.value)} Z` : "",
);
const peak = computed(() => coords.value.findIndex((c) => c.value === max.value && c.value > 0));
const last = computed(() => coords.value[coords.value.length - 1]);
const ticks = computed(() => [0, 0.5, 1].map((f) => { const v = lo.value + (hi.value - lo.value) * f; return { v, y: y(v) }; }));
const slot = computed(() => (props.points.length > 1 ? (W - PAD.left - PAD.right) / (props.points.length - 1) : W));
</script>

<template>
  <div>
    <svg :viewBox="`0 0 ${W} ${H}`" class="block h-auto w-full" role="img">
      <g v-for="t in ticks" :key="t.v" class="text-muted-foreground">
        <line :x1="PAD.left" :x2="W - PAD.right" :y1="t.y" :y2="t.y" class="stroke-border" stroke-width="1" vector-effect="non-scaling-stroke" />
        <text :x="PAD.left - 8" :y="t.y + 4" text-anchor="end" font-size="11" fill="currentColor">{{ zeroBased ? compact.format(t.v) : fmt(t.v) }}</text>
      </g>
      <path :d="area" class="fill-primary/10" />
      <path :d="line" fill="none" class="stroke-primary" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke" />
      <g v-for="(c, i) in coords" :key="c.date" class="group">
        <rect :x="c.x - slot / 2" :y="0" :width="slot" :height="H" fill="transparent">
          <title>{{ day(c.date) }}: {{ fmt(c.value) }}</title>
        </rect>
        <line :x1="c.x" :x2="c.x" :y1="PAD.top" :y2="y(lo)" class="stroke-muted-foreground/40 opacity-0 group-hover:opacity-100" stroke-width="1" vector-effect="non-scaling-stroke" />
        <circle :cx="c.x" :cy="c.y" r="4" class="fill-primary stroke-card opacity-0 group-hover:opacity-100" stroke-width="2" />
        <text
          v-if="i === peak"
          :x="c.x"
          :y="c.y - 10"
          text-anchor="middle"
          font-size="11"
          class="text-muted-foreground"
          fill="currentColor"
        >
          {{ fmt(c.value) }}
        </text>
      </g>
      <circle v-if="last" :cx="last.x" :cy="last.y" r="4" class="fill-brand-strong stroke-card" stroke-width="2" />
    </svg>
    <div class="border-border text-muted-foreground flex justify-between border-t pt-1 pl-11 text-[10px]">
      <span>{{ points.length ? day(points[0].date) : "" }}</span>
      <span>{{ points.length ? day(points[points.length - 1].date) : "" }}</span>
    </div>
  </div>
</template>
