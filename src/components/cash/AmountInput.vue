<script setup lang="ts">
import MoneyInput from "@/components/common/MoneyInput.vue";
import { FIELD_CLASS } from "@/lib/utils";

defineProps<{ currency: string; base: string; id?: string; required?: boolean; disabled?: boolean; negative?: boolean; ariaLabel?: string }>();
const model = defineModel<number | null>({ required: true });
</script>

<template>
  <MoneyInput v-if="currency === base" :id="id" v-model="model" :negative="negative" :required="required" :disabled="disabled" :aria-label="ariaLabel" />
  <div v-else class="relative">
    <input
      :id="id"
      :value="model ?? ''"
      type="number"
      step="0.01"
      :min="negative ? undefined : 0"
      :required="required"
      :disabled="disabled"
      :aria-label="ariaLabel"
      :class="[FIELD_CLASS, 'pl-12 text-right tabular-nums']"
      @input="model = ($event.target as HTMLInputElement).value === '' ? null : Number(($event.target as HTMLInputElement).value)"
    />
    <span class="text-muted-foreground pointer-events-none absolute inset-y-0 left-2.5 flex items-center text-xs font-semibold">{{ currency }}</span>
  </div>
</template>
