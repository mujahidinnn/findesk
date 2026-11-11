<script setup lang="ts">
import { useAuthStore } from "@/stores/auth";
import type { Action } from "@/lib/types";

const props = withDefaults(defineProps<{ feature: string; action?: Action }>(), { action: "read" });
const auth = useAuthStore();
</script>

<template>
  <slot v-if="auth.can(props.feature, props.action)" />
  <slot v-else name="fallback" />
</template>
