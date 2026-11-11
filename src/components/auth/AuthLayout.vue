<script setup lang="ts">
import { useI18n } from "vue-i18n";
import LogoMark from "@/components/brand/LogoMark.vue";

const { t } = useI18n();
const SAMPLE = [
  [46, 38], [62, 48], [70, 56], [58, 34], [40, 38], [44, 26], [38, 30], [60, 54], [46, 40], [90, 58], [24, 16],
];
</script>

<template>
  <div class="bg-background max-lg:bg-brand-gradient grid min-h-dvh max-lg:flex max-lg:flex-col lg:grid-cols-2">
    <header class="relative space-y-4 overflow-hidden px-6 pt-10 pb-10 text-white sm:px-12 lg:hidden">
      <div class="pointer-events-none absolute -top-24 -right-16 size-64 rounded-full bg-brand-400/35 blur-3xl" aria-hidden="true" />
      <div class="pointer-events-none absolute top-24 -left-20 size-56 rounded-full bg-brand-300/20 blur-3xl" aria-hidden="true" />
      <svg class="pointer-events-none absolute -top-10 -right-10 size-72 text-white/15" viewBox="0 0 200 200" fill="none" stroke="currentColor" stroke-width="0.6" aria-hidden="true">
        <circle cx="100" cy="100" r="30" /><circle cx="100" cy="100" r="50" /><circle cx="100" cy="100" r="70" /><circle cx="100" cy="100" r="90" />
        <path d="M100 10v180M10 100h180" stroke-dasharray="2 4" />
      </svg>
      <div class="pointer-events-none absolute inset-x-0 bottom-0 h-px bg-linear-to-r from-transparent via-white/30 to-transparent" aria-hidden="true" />
      <div class="relative flex items-center gap-2.5">
        <LogoMark class="size-8" />
        <p class="text-lg font-semibold tracking-tight">FinDesk</p>
      </div>
      <p class="relative text-2xl leading-tight font-semibold tracking-tight">{{ t("app.tagline") }}</p>
      <p class="relative text-sm text-white/75">{{ t("login.pitch") }}</p>
    </header>

    <div class="max-lg:bg-background max-lg:text-foreground flex flex-col px-6 py-10 max-lg:flex-1 max-lg:rounded-t-3xl max-lg:pt-8 max-lg:pb-6 sm:px-12 lg:px-16">
      <div class="flex items-center gap-3 max-lg:hidden">
        <LogoMark color class="size-10" />
        <div>
          <p class="text-lg leading-tight font-semibold tracking-tight">FinDesk</p>
          <p class="text-muted-foreground text-sm leading-tight">{{ t("app.short") }}</p>
        </div>
      </div>
      <main class="mx-auto my-auto w-full max-w-md py-10 max-lg:py-4">
        <slot />
      </main>
      <p class="text-muted-foreground text-center text-[11px]">{{ t("app.copyright", { year: new Date().getFullYear() }) }}</p>
    </div>

    <aside class="bg-brand-gradient relative m-4 hidden flex-col justify-center gap-10 overflow-hidden rounded-xl p-12 lg:flex xl:p-16" aria-hidden="true">
      <div class="pointer-events-none absolute -top-24 -right-16 size-96 rounded-full bg-brand-400/35 blur-3xl" />
      <svg class="pointer-events-none absolute -top-16 -right-16 size-120 text-white/15" viewBox="0 0 200 200" fill="none" stroke="currentColor" stroke-width="0.6">
        <circle cx="100" cy="100" r="30" /><circle cx="100" cy="100" r="50" /><circle cx="100" cy="100" r="70" /><circle cx="100" cy="100" r="90" />
        <path d="M100 10v180M10 100h180" stroke-dasharray="2 4" />
      </svg>
      <div class="relative max-w-lg">
        <p class="text-3xl leading-tight font-semibold tracking-tight xl:text-4xl">{{ t("app.tagline") }}</p>
        <p class="mt-4 text-base leading-relaxed text-white/70">{{ t("login.pitch") }}</p>
      </div>

      <div class="relative max-w-xl pb-10 pr-10">
        <div class="bg-card text-card-foreground rounded-xl border p-5 shadow-xl">
          <p class="text-muted-foreground text-sm font-medium">{{ t("dashboard.monthly") }}</p>
          <div class="text-muted-foreground mt-2 flex gap-4 text-xs">
            <span class="flex items-center gap-1.5"><span class="bg-brand-500 size-2.5 rounded-xs" />{{ t("dashboard.revenue") }}</span>
            <span class="flex items-center gap-1.5"><span class="bg-brand-200 size-2.5 rounded-xs" />{{ t("dashboard.expense") }}</span>
          </div>
          <div class="border-border mt-4 flex h-40 items-end justify-between gap-2 border-b">
            <div v-for="(m, i) in SAMPLE" :key="i" class="flex h-full flex-1 items-end justify-center gap-1">
              <span class="bg-brand-500 w-2.5 rounded-t-sm" :style="{ height: `${m[0]}%` }" />
              <span class="bg-brand-200 w-2.5 rounded-t-sm" :style="{ height: `${m[1]}%` }" />
            </div>
          </div>
        </div>

        <div class="bg-card text-card-foreground absolute right-0 bottom-0 flex items-center gap-4 rounded-xl border p-4 shadow-xl">
          <svg viewBox="0 0 42 42" class="size-16 -rotate-90">
            <circle cx="21" cy="21" r="15.9" fill="none" class="stroke-brand-100" stroke-width="7" />
            <circle cx="21" cy="21" r="15.9" fill="none" class="stroke-brand-600" stroke-width="7" stroke-dasharray="52 48" />
            <circle cx="21" cy="21" r="15.9" fill="none" class="stroke-brand-300" stroke-width="7" stroke-dasharray="26 74" stroke-dashoffset="-52" />
          </svg>
          <span class="space-y-2">
            <span class="bg-brand-600 block h-2 w-24 rounded-full" />
            <span class="bg-brand-300 block h-2 w-16 rounded-full" />
            <span class="bg-brand-100 block h-2 w-10 rounded-full" />
          </span>
        </div>
      </div>
    </aside>
  </div>
</template>
