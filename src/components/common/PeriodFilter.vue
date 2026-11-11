<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { CalendarDays } from "@lucide/vue";
import { Input } from "@/components/ui/input";
import { isoDate } from "@/lib/format";

const from = defineModel<string>("from", { required: true });
const to = defineModel<string>("to", { required: true });
const { t } = useI18n();

const daysAgo = (n: number) => isoDate(new Date(Date.now() - n * 86400000));
const monthStart = () => isoDate().slice(0, 8) + "01";
const lastMonth = () => {
  const d = new Date();
  return { from: isoDate(new Date(d.getFullYear(), d.getMonth() - 1, 1)), to: isoDate(new Date(d.getFullYear(), d.getMonth(), 0)) };
};
const PRESETS = {
  "7d": () => ({ from: daysAgo(6), to: isoDate() }),
  "30d": () => ({ from: daysAgo(29), to: isoDate() }),
  month: () => ({ from: monthStart(), to: isoDate() }),
  lastMonth,
} as const;
type Key = keyof typeof PRESETS | "custom";
const KEYS: Key[] = ["7d", "30d", "month", "lastMonth", "custom"];

const forcedCustom = ref(false);
const active = computed<Key>(() => {
  if (forcedCustom.value) return "custom";
  const hit = (Object.keys(PRESETS) as (keyof typeof PRESETS)[]).find((k) => {
    const r = PRESETS[k]();
    return r.from === from.value && r.to === to.value;
  });
  return hit ?? "custom";
});
function pick(k: Key) {
  forcedCustom.value = k === "custom";
  if (k !== "custom") ({ from: from.value, to: to.value } = PRESETS[k]());
}
const fmt = (iso: string, year = false) => new Date(`${iso}T00:00`).toLocaleDateString("id-ID", { day: "numeric", month: "short", ...(year && { year: "numeric" }) });
const label = computed(() => (from.value === to.value ? fmt(to.value, true) : `${fmt(from.value)} - ${fmt(to.value, true)}`));
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <div role="radiogroup" :aria-label="t('period.label')" class="bg-card flex h-9 [scrollbar-width:none] max-w-full items-center gap-0.5 overflow-x-auto rounded-md border p-1">
      <button
        v-for="k in KEYS"
        :key="k"
        type="button"
        role="radio"
        :aria-checked="active === k"
        :class="['h-full shrink-0 rounded-sm px-3 text-xs font-medium whitespace-nowrap transition-colors', active === k ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-secondary hover:text-foreground']"
        @click="pick(k)"
      >
        {{ t(`period.presets.${k}`) }}
      </button>
    </div>
    <template v-if="active === 'custom'">
      <Input v-model="from" type="date" class="h-9 w-40" :aria-label="t('period.from')" />
      <span class="text-muted-foreground text-xs">-</span>
      <Input v-model="to" type="date" class="h-9 w-40" :aria-label="t('period.to')" />
    </template>
    <span v-else class="bg-card text-muted-foreground flex h-9 items-center gap-2 rounded-md border px-3 text-xs">
      <CalendarDays class="size-3.5" /> {{ label }}
    </span>
  </div>
</template>
