<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { LoaderCircle } from "@lucide/vue";

type Variant = "table" | "grid" | "cards" | "bars" | "line" | "donut" | "list" | "form" | "product" | "detail" | "hero" | "inline";
withDefaults(defineProps<{ variant?: Variant; label?: string; columns?: number; rows?: number }>(), {
  variant: "table",
  label: undefined,
  columns: 5,
  rows: 6,
});
const { t } = useI18n();
const BARS = [92, 78, 66, 58, 47, 39, 30, 22];
const W = [70, 45, 85, 55, 65, 40, 75, 50];
</script>

<template>
  <div role="status" aria-live="polite" class="fade-in-late">
    <span class="sr-only">{{ label ?? t("common.loading") }}</span>
    <div v-if="variant === 'table'" class="bg-card overflow-hidden rounded-xl border" aria-hidden="true">
      <div class="flex gap-4 border-b px-3 py-2.5">
        <span v-for="c in columns" :key="c" class="shimmer h-3 flex-1" :style="{ maxWidth: c === columns ? '3rem' : `${W[c % 8]}%` }" />
      </div>
      <div v-for="r in rows" :key="r" class="flex items-center gap-4 border-b px-3 py-3 last:border-0">
        <span v-for="c in columns" :key="c" class="shimmer h-4 flex-1" :style="{ maxWidth: c === columns ? '3rem' : `${W[(r + c) % 8]}%` }" />
      </div>
    </div>
    <div v-else-if="variant === 'grid'" class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5" aria-hidden="true">
      <div v-for="i in rows === 6 ? 10 : rows" :key="i" class="bg-card overflow-hidden rounded-xl border">
        <span class="shimmer block aspect-[4/3] rounded-none" />
        <div class="space-y-2 p-3"><span class="shimmer block h-4 w-4/5" /><span class="shimmer block h-3 w-1/2" /></div>
      </div>
    </div>
    <div
      v-else-if="variant === 'cards'"
      class="grid gap-4 sm:grid-cols-2 lg:[grid-template-columns:repeat(var(--n),minmax(0,1fr))]"
      :style="{ '--n': rows === 6 ? 4 : rows }"
      aria-hidden="true"
    >
      <div v-for="i in rows === 6 ? 4 : rows" :key="i" class="bg-card space-y-3 rounded-xl border p-4">
        <div class="flex items-center gap-2"><span class="shimmer size-8 rounded-lg" /><span class="shimmer h-3 w-24" /></div>
        <span class="shimmer block h-8 w-32" /><span class="shimmer block h-3 w-20" />
      </div>
    </div>
    <div v-else-if="variant === 'bars'" class="space-y-2.5" aria-hidden="true">
      <div v-for="(w, i) in BARS.slice(0, rows)" :key="i" class="flex items-center gap-3">
        <span class="shimmer h-3 w-32 shrink-0 sm:w-40" /><span class="shimmer h-5" :style="{ width: `${w * 0.7}%` }" />
      </div>
    </div>
    <div v-else-if="variant === 'line'" class="relative h-48" aria-hidden="true">
      <div class="absolute inset-0 flex flex-col justify-between"><span v-for="i in 4" :key="i" class="border-border/60 border-t border-dashed" /></div>
      <svg viewBox="0 0 100 40" preserveAspectRatio="none" class="absolute inset-0 size-full animate-pulse">
        <path d="M0 30 C10 26 18 32 28 22 S45 12 55 18 S72 28 82 14 S95 10 100 12 L100 40 L0 40 Z" class="fill-stone-500/10" />
        <path d="M0 30 C10 26 18 32 28 22 S45 12 55 18 S72 28 82 14 S95 10 100 12" class="fill-none stroke-stone-500/25" stroke-width="0.8" />
      </svg>
    </div>
    <div v-else-if="variant === 'donut'" class="flex items-center gap-5" aria-hidden="true">
      <span class="size-32 shrink-0 animate-pulse rounded-full border-[14px] border-stone-500/10" />
      <div class="flex-1 space-y-2.5">
        <div v-for="i in 4" :key="i" class="flex items-center gap-2"><span class="shimmer size-2.5 rounded-xs" /><span class="shimmer h-3 flex-1" :style="{ maxWidth: `${W[i]}%` }" /><span class="shimmer h-3 w-8" /></div>
      </div>
    </div>
    <ul v-else-if="variant === 'list'" class="divide-y" aria-hidden="true">
      <li v-for="i in rows === 6 ? 5 : rows" :key="i" class="flex items-center gap-3 py-2.5">
        <span class="shimmer size-8 shrink-0 rounded-lg" />
        <div class="flex-1 space-y-1.5"><span class="shimmer block h-3.5" :style="{ width: `${W[i]}%` }" /><span class="shimmer block h-2.5 w-24" /></div>
        <div class="space-y-1.5"><span class="shimmer block h-3.5 w-20" /><span class="shimmer ml-auto block h-2.5 w-12" /></div>
      </li>
    </ul>
    <div v-else-if="variant === 'form'" class="bg-card max-w-xl space-y-4 rounded-xl border p-5" aria-hidden="true">
      <div v-for="i in rows === 6 ? 4 : rows" :key="i" class="space-y-1.5"><span class="shimmer block h-3 w-24" /><span class="shimmer block h-9 w-full" /></div>
      <span class="shimmer ml-auto block h-9 w-28" />
    </div>
    <div v-else-if="variant === 'product'" class="grid gap-8 md:grid-cols-2" aria-hidden="true">
      <span class="shimmer block aspect-square" />
      <div class="space-y-4 py-2">
        <span class="shimmer block h-3 w-24" /><span class="shimmer block h-8 w-4/5" /><span class="shimmer block h-7 w-40" />
        <div class="space-y-2 pt-2"><span class="shimmer block h-3 w-full" /><span class="shimmer block h-3 w-11/12" /><span class="shimmer block h-3 w-2/3" /></div>
        <div class="flex gap-2 pt-4"><span class="shimmer h-10 w-40" /><span class="shimmer h-10 w-10" /></div>
      </div>
    </div>
    <div v-else-if="variant === 'detail'" class="space-y-5" aria-hidden="true">
      <div class="flex items-start gap-3">
        <div class="flex-1 space-y-2"><span class="shimmer block h-8 w-56" /><span class="shimmer block h-3 w-72" /></div>
        <span class="shimmer h-8 w-24" /><span class="shimmer h-8 w-32" />
      </div>
      <div class="grid gap-5 lg:grid-cols-12">
        <div class="bg-card space-y-4 rounded-xl border p-5 lg:col-span-8">
          <div v-for="i in 4" :key="i" class="flex items-center gap-4">
            <span class="shimmer size-16 shrink-0 rounded-xl" />
            <div class="flex-1 space-y-2"><span class="shimmer block h-4" :style="{ width: `${W[i]}%` }" /><span class="shimmer block h-3 w-28" /></div>
            <span class="shimmer h-4 w-24" />
          </div>
        </div>
        <div class="space-y-5 lg:col-span-4">
          <div v-for="i in 2" :key="i" class="bg-card space-y-3 rounded-xl border p-5"><span class="shimmer block h-4 w-32" /><span class="shimmer block h-3 w-full" /><span class="shimmer block h-3 w-3/4" /><span class="shimmer block h-3 w-1/2" /></div>
        </div>
      </div>
    </div>
    <div v-else-if="variant === 'hero'" class="grid gap-4 lg:grid-cols-[1fr_minmax(0,18rem)]" aria-hidden="true">
      <span class="shimmer block min-h-72 rounded-xl" />
      <div class="hidden gap-4 lg:grid"><span class="shimmer block rounded-xl" /><span class="shimmer block rounded-xl" /></div>
    </div>
    <div v-else class="text-muted-foreground flex items-center justify-center gap-2 py-6 text-xs">
      <LoaderCircle class="size-4 animate-spin" /> {{ label ?? t("common.loading") }}
    </div>
  </div>
</template>
