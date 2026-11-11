<script setup lang="ts">
import type { Component } from "vue";

defineProps<{ icon?: Component; title: string; description?: string; compact?: boolean }>();
</script>

<template>
  <div :class="['flex flex-col items-center justify-center px-4 text-center', compact ? 'py-4' : 'py-10']">
    <svg :class="compact ? 'h-16' : 'h-28'" viewBox="0 0 160 120" fill="none" aria-hidden="true">
      <rect x="40" y="10" width="92" height="104" rx="4" transform="rotate(6 86 62)" class="fill-brand-500/8 stroke-brand-300" stroke-width="1.5" />
      <rect x="28" y="8" width="96" height="106" rx="4" class="fill-card stroke-brand-400" stroke-width="2" />
      <line x1="28" y1="26" x2="124" y2="26" class="stroke-brand-400" stroke-width="2" />
      <line x1="46" y1="8" x2="46" y2="114" class="stroke-rose-400/60" stroke-width="1.5" />
      <line x1="88" y1="26" x2="88" y2="114" class="stroke-brand-300" stroke-width="1.5" />
      <line x1="106" y1="26" x2="106" y2="114" class="stroke-brand-300" stroke-width="1.5" />
      <g class="stroke-brand-200 dark:stroke-brand-800" stroke-width="1.5">
        <line x1="28" y1="40" x2="124" y2="40" /><line x1="28" y1="54" x2="124" y2="54" /><line x1="28" y1="68" x2="124" y2="68" />
        <line x1="28" y1="82" x2="124" y2="82" />
      </g>
      <rect x="52" y="15" width="28" height="5" rx="2.5" class="fill-brand-400" />
      <line x1="28" y1="98" x2="124" y2="98" class="stroke-brand-400" stroke-width="2" stroke-dasharray="4 3" />
      <text v-if="!icon" x="115" y="109" text-anchor="middle" font-size="7.5" font-weight="600" class="fill-brand-500 font-mono">0,00</text>
      <foreignObject v-else x="58" y="56" width="24" height="24">
        <component :is="icon" class="size-6 text-brand-500" />
      </foreignObject>
    </svg>
    <p :class="['font-medium', compact ? 'mt-2 text-xs' : 'mt-3 text-sm']">{{ title }}</p>
    <p v-if="description" class="text-muted-foreground mt-1 max-w-xs text-xs">{{ description }}</p>
    <div v-if="$slots.default" class="mt-4"><slot /></div>
  </div>
</template>
