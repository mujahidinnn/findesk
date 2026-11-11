<script setup lang="ts" generic="T extends string | number">
import type { HTMLAttributes } from "vue";
import { computed } from "vue";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";

export interface SelectOption<T> {
  value: T;
  label: string;
  disabled?: boolean;
}

const props = defineProps<{
  modelValue: T | null | undefined;
  options: SelectOption<T>[];
  nullLabel?: string;
  placeholder?: string;
  id?: string;
  disabled?: boolean;
  required?: boolean;
  size?: "sm" | "default";
  class?: HTMLAttributes["class"];
  ariaLabel?: string;
}>();
const emit = defineEmits<{ "update:modelValue": [value: T | null] }>();

const NONE = "__none__";
const inner = computed({
  get: () => (props.modelValue == null ? (props.nullLabel != null ? NONE : undefined) : String(props.modelValue)),
  set: (k: string | undefined) => {
    if (k == null) return;
    if (k === NONE) return emit("update:modelValue", null);
    const o = props.options.find((x) => String(x.value) === k);
    emit("update:modelValue", o ? o.value : (k as T));
  },
});
</script>

<template>
  <Select v-model="inner" :disabled="disabled" :required="required">
    <SelectTrigger :id="id" :size="size ?? 'default'" :class="cn('bg-background w-full', props.class)" :aria-label="ariaLabel">
      <SelectValue :placeholder="placeholder ?? nullLabel" />
    </SelectTrigger>
    <SelectContent>
      <SelectItem v-if="nullLabel != null" :value="NONE">{{ nullLabel }}</SelectItem>
      <SelectItem v-for="o in options" :key="o.value" :value="String(o.value)" :disabled="o.disabled">{{ o.label }}</SelectItem>
    </SelectContent>
  </Select>
</template>
