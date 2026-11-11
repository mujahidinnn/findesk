<script setup lang="ts">
import { computed } from "vue";

export interface BarRow {
  label: string;
  value: number;
  hint?: string;
  segments?: number[];
  href?: string;
  image?: string | null;
}

const props = defineProps<{ rows: BarRow[]; legend?: string[]; format?: (n: number) => string }>();
const SEGMENT = ["bg-brand-200", "bg-brand-400", "bg-brand-600", "bg-brand-800"];
const fmt = (n: number) => (props.format ?? ((v: number) => v.toLocaleString("id-ID")))(n);
const max = computed(() => Math.max(1, ...props.rows.map((r) => r.value)));
const width = (v: number) => `${Math.max(0, (v / max.value) * 100)}%`;
</script>

<template>
  <div class="space-y-2">
    <div v-if="legend" class="text-muted-foreground flex flex-wrap gap-x-3 gap-y-1 text-xs">
      <span v-for="(l, i) in legend" :key="l" class="flex items-center gap-1.5">
        <span :class="['inline-block size-2.5 rounded-xs', SEGMENT[i]]" /> {{ l }}
      </span>
    </div>
    <div
      v-for="r in rows"
      :key="r.label"
      class="group flex items-center gap-3 text-sm"
      :title="`${r.label}: ${fmt(r.value)}${r.hint ? ` · ${r.hint}` : ''}`"
    >
      <component
        :is="r.href ? 'RouterLink' : 'span'"
        :to="r.href"
        :class="['text-muted-foreground flex w-32 shrink-0 items-center gap-2 text-xs sm:w-40', r.href && 'hover:text-foreground hover:underline']"
      >
        <span class="truncate">{{ r.label }}</span>
      </component>
      <div class="border-border h-5 flex-1 border-l">
        <div class="flex h-full gap-0.5 transition-[filter] group-hover:brightness-95" :style="{ width: width(r.value) }">
          <template v-if="r.segments">
            <div
              v-for="(s, i) in r.segments"
              :key="i"
              :class="['h-full last:rounded-r', SEGMENT[i]]"
              :style="{ flex: `${s} 0 0` }"
            />
          </template>
          <div v-else class="bg-primary h-full w-full rounded-r" />
        </div>
      </div>
      <span class="w-24 shrink-0 text-right text-xs tabular-nums">{{ fmt(r.value) }}</span>
    </div>
  </div>
</template>
