<script setup lang="ts">
import type { HTMLAttributes } from "vue";
import { computed } from "vue";
import { cn } from "@/lib/utils";

const props = defineProps<{
  modelValue: number | string | null | undefined;
  id?: string;
  max?: number;
  negative?: boolean;
  required?: boolean;
  disabled?: boolean;
  placeholder?: string;
  class?: HTMLAttributes["class"];
  ariaLabel?: string;
}>();
const emit = defineEmits<{ "update:modelValue": [value: number | null] }>();

const fmt = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 0 });
const text = computed(() => (props.modelValue === null || props.modelValue === undefined || props.modelValue === "" ? "" : fmt.format(Number(props.modelValue))));

function onInput(e: Event) {
  const el = e.target as HTMLInputElement;
  const minus = !!props.negative && el.value.trimStart().startsWith("-");
  const digits = el.value.replace(/\D/g, "");
  let value = digits ? Number(digits) * (minus ? -1 : 1) : null;
  if (value !== null && props.max !== undefined && value > props.max) value = props.max;
  emit("update:modelValue", value);
  el.value = value === null ? (minus ? "-" : "") : fmt.format(value);
}
</script>

<template>
  <div
    :class="cn(
      'border-input bg-background focus-within:ring-ring/50 flex h-9 w-full items-center overflow-hidden rounded-md border text-sm focus-within:ring-3',
      disabled && 'opacity-50',
      props.class,
    )"
  >
    <span class="bg-secondary text-muted-foreground flex h-full items-center border-r px-2.5 text-xs font-semibold">Rp</span>
    <input
      :id="id"
      :value="text"
      type="text"
      inputmode="numeric"
      autocomplete="off"
      :required="required"
      :disabled="disabled"
      :placeholder="placeholder ?? '0'"
      :aria-label="ariaLabel"
      class="h-full min-w-0 flex-1 bg-transparent px-2.5 text-right tabular-nums outline-none"
      @input="onInput"
    />
  </div>
</template>
