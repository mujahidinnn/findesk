<script setup lang="ts">
import type { HTMLAttributes } from "vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import { cn, FIELD_CLASS } from "@/lib/utils";

defineProps<{ currency: string; id?: string; max?: number; required?: boolean; disabled?: boolean; class?: HTMLAttributes["class"]; ariaLabel?: string }>();
const value = defineModel<number | null>({ required: true });
</script>

<template>
  <MoneyInput v-if="currency === 'IDR'" :id="id" v-model="value" :max="max" :required="required" :disabled="disabled" :class="$props.class" :aria-label="ariaLabel" />
  <input
    v-else
    :id="id"
    :value="value ?? ''"
    type="number"
    step="0.01"
    min="0"
    :max="max"
    :required="required"
    :disabled="disabled"
    :aria-label="ariaLabel"
    :class="cn(FIELD_CLASS, 'text-right tabular-nums', $props.class)"
    @input="value = ($event.target as HTMLInputElement).value === '' ? null : Number(($event.target as HTMLInputElement).value)"
  />
</template>
