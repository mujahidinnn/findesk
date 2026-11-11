<script setup lang="ts">
import { useId } from "vue";

defineProps<{ animated?: boolean; color?: boolean }>();
const id = useId();
</script>

<template>
  <svg viewBox="0 0 24 24" aria-hidden="true" :class="{ 'logo-draw': animated }">
    <defs>
      <linearGradient :id="`${id}-g`" gradientUnits="userSpaceOnUse" x1="20" y1="3" x2="4" y2="21">
        <stop offset="0" stop-color="#8C9BF2" />
        <stop offset="1" stop-color="#2B3FA0" />
      </linearGradient>
    </defs>
    <g :fill="color ? `url(#${id}-g)` : 'currentColor'">
      <rect x="3.5" y="3" width="3.4" height="18" rx="1.7" />
      <rect x="3.5" y="3" width="17" height="3.4" rx="1.7" />
      <rect x="3.5" y="10.3" width="11.5" height="3.4" rx="1.7" />
    </g>
    <circle cx="16.6" cy="17.6" r="3.2" pathLength="1" fill="none" :stroke="color ? `url(#${id}-g)` : 'currentColor'" stroke-width="2.1" />
  </svg>
</template>
