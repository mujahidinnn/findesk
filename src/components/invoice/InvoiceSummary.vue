<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { AlarmClock, CalendarRange, Wallet } from "@lucide/vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { openOf, type Side } from "@/components/invoice/docTypes";
import { useMasterRows } from "@/composables/useMasterRows";
import { formatMoney, isoDate, monthStart, round2 } from "@/lib/format";

const props = defineProps<{ side: Side }>();
const { t } = useI18n();
const main = computed(() => (props.side === "sales" ? "sales_invoice" : "purchase_bill"));

const rows = useMasterRows("t_invoices", {
  columns: "id, doc_type, status, total, paid_amount, fx_rate, invoice_date, due_date",
  filter: () => ({ doc_type: main.value }),
});
const stats = computed(() => {
  const today = isoDate();
  const from = monthStart();
  let open = 0, overdue = 0, overdueCount = 0, month = 0;
  for (const r of rows.data.value ?? []) {
    const base = (v: number) => v * Number(r.fx_rate);
    if (r.status === "posted") {
      open += base(openOf(r));
      if (r.due_date && String(r.due_date) < today) {
        overdue += base(openOf(r));
        overdueCount++;
      }
    }
    if ((r.status === "posted" || r.status === "paid") && String(r.invoice_date) >= from) month += base(Number(r.total));
  }
  return { open: round2(open), overdue: round2(overdue), overdueCount, month: round2(month) };
});
const cards = computed(() => [
  { key: "open", icon: Wallet, value: stats.value.open, hint: "" },
  { key: "overdue", icon: AlarmClock, value: stats.value.overdue, hint: t("invoices.summary.docs", { n: stats.value.overdueCount }) },
  { key: "month", icon: CalendarRange, value: stats.value.month, hint: "" },
]);
</script>

<template>
  <LoadingState v-if="rows.isPending.value" variant="cards" :rows="3" />
  <div v-else class="grid gap-3 sm:grid-cols-3">
    <div v-for="c in cards" :key="c.key" class="bg-card rounded-xl border p-4">
      <p class="text-muted-foreground flex items-center gap-2 text-xs">
        <component :is="c.icon" class="size-4" /> {{ t(`invoices.summary.${side}.${c.key}`) }}
      </p>
      <p class="mt-2 text-xl font-semibold tabular-nums" :class="c.key === 'overdue' && c.value > 0 && 'text-rose-600'">{{ formatMoney(c.value) }}</p>
      <p v-if="c.hint" class="text-muted-foreground mt-0.5 text-xs">{{ c.hint }}</p>
    </div>
  </div>
</template>
