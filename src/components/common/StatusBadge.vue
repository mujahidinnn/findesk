<script setup lang="ts">
import { cn } from "@/lib/utils";

export type Tone = "success" | "warning" | "danger" | "info" | "muted";

const TONES: Record<Tone, string> = {
  success: "bg-green-500/15 text-green-700 dark:text-green-400",
  warning: "bg-orange-100 text-orange-700 dark:bg-orange-500/15 dark:text-orange-300",
  danger: "bg-rose-500/10 text-rose-700 dark:text-rose-400",
  info: "bg-sky-500/10 text-sky-700 dark:text-sky-400",
  muted: "bg-muted text-muted-foreground",
};

defineProps<{ tone: Tone }>();
</script>

<template>
  <span :class="cn('inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap', TONES[tone])">
    <slot />
  </span>
</template>
