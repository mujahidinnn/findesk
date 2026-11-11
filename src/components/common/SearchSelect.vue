<script setup lang="ts" generic="T extends string | number">
import { computed, ref, type HTMLAttributes } from "vue";
import { useI18n } from "vue-i18n";
import { Check, ChevronsUpDown } from "@lucide/vue";
import {
  ComboboxAnchor, ComboboxContent, ComboboxEmpty, ComboboxInput, ComboboxItem, ComboboxItemIndicator, ComboboxPortal,
  ComboboxRoot, ComboboxTrigger, ComboboxViewport,
} from "reka-ui";
import { cn } from "@/lib/utils";

export interface SearchOption<T> { value: T; label: string }
const props = defineProps<{
  modelValue: T | null | undefined;
  options: SearchOption<T>[];
  placeholder?: string;
  nullLabel?: string;
  id?: string;
  disabled?: boolean;
  required?: boolean;
  class?: HTMLAttributes["class"];
  ariaLabel?: string;
}>();
const emit = defineEmits<{ "update:modelValue": [value: T | null] }>();
const { t } = useI18n();
const query = ref("");

const selected = computed(() => props.options.find((o) => o.value === props.modelValue) ?? null);
const shown = computed(() => {
  const q = query.value.trim().toLowerCase();
  const list = q ? props.options.filter((o) => o.label.toLowerCase().includes(q)) : props.options;
  return list.slice(0, 200);
});
function pick(v: unknown) {
  emit("update:modelValue", v == null ? null : (v as SearchOption<T>).value);
  query.value = "";
}
</script>

<template>
  <ComboboxRoot :model-value="selected" :disabled="disabled" ignore-filter :by="(a: SearchOption<T> | null, b: SearchOption<T> | null) => a?.value === b?.value" @update:model-value="pick">
    <ComboboxAnchor
      :class="cn('border-input bg-background focus-within:ring-ring/50 flex h-9 w-full min-w-0 items-center rounded-md border text-sm focus-within:ring-3', disabled && 'opacity-50', props.class)"
    >
      <ComboboxInput
        :id="id"
        v-model="query"
        :display-value="(o: SearchOption<T> | null) => o?.label ?? ''"
        :placeholder="selected?.label ?? placeholder ?? nullLabel ?? t('common.pick')"
        :required="required && modelValue == null"
        :aria-label="ariaLabel"
        class="placeholder:text-muted-foreground h-full min-w-0 flex-1 bg-transparent px-3 outline-none"
      />
      <ComboboxTrigger class="text-muted-foreground px-2"><ChevronsUpDown class="size-4" /></ComboboxTrigger>
    </ComboboxAnchor>
    <ComboboxPortal>
      <ComboboxContent
        position="popper"
        :side-offset="4"
        class="bg-popover text-popover-foreground z-50 max-h-72 w-(--reka-combobox-trigger-width) min-w-56 overflow-hidden rounded-md border shadow-md"
      >
        <ComboboxViewport class="max-h-72 overflow-y-auto p-1">
          <ComboboxEmpty class="text-muted-foreground px-2 py-3 text-center text-xs">{{ t("common.noOptions") }}</ComboboxEmpty>
          <ComboboxItem
            v-if="nullLabel != null"
            :value="null as unknown as SearchOption<T>"
            class="data-highlighted:bg-accent flex cursor-default items-center rounded-sm px-2 py-1.5 text-sm outline-none"
          >
            {{ nullLabel }}
          </ComboboxItem>
          <ComboboxItem
            v-for="o in shown"
            :key="String(o.value)"
            :value="o"
            class="data-highlighted:bg-accent flex cursor-default items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-none"
          >
            <span class="min-w-0 flex-1 truncate">{{ o.label }}</span>
            <ComboboxItemIndicator><Check class="size-4" /></ComboboxItemIndicator>
          </ComboboxItem>
        </ComboboxViewport>
      </ComboboxContent>
    </ComboboxPortal>
  </ComboboxRoot>
</template>
