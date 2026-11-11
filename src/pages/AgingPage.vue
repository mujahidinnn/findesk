<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronRight, HandCoins, Receipt, RefreshCw } from "@lucide/vue";
import BarChart from "@/components/charts/BarChart.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import TabBar from "@/components/common/TabBar.vue";
import { Button } from "@/components/ui/button";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useTabParam } from "@/composables/useTabParam";
import { formatAmount, formatDate, formatMoney, isoDate, round2 } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const { t } = useI18n();
const SIDES = ["receivable", "payable"] as const;
const BUCKETS = ["current", "d1_30", "d31_60", "d61_90", "d90_plus"] as const;
type Bucket = (typeof BUCKETS)[number];
const side = useTabParam(() => SIDES);
const tabs = computed(() => [
  { key: SIDES[0], label: t("aging.receivable"), icon: Receipt },
  { key: SIDES[1], label: t("aging.payable"), icon: HandCoins },
]);
const asOf = ref(isoDate());
const query = useRpcQuery("aging", () => (side.value && asOf.value ? { p_side: side.value, p_as_of: asOf.value } : null));

type Doc = NonNullable<typeof query.data.value>[number];
interface Group { partnerId: number; partner: string; docs: Doc[]; buckets: Record<Bucket, number>; total: number }
const zero = () => Object.fromEntries(BUCKETS.map((b) => [b, 0])) as Record<Bucket, number>;
const groups = computed(() => {
  const map = new Map<number, Group>();
  for (const d of query.data.value ?? []) {
    let g = map.get(d.partner_id);
    if (!g) map.set(d.partner_id, (g = { partnerId: d.partner_id, partner: d.partner, docs: [], buckets: zero(), total: 0 }));
    g.docs.push(d);
    g.buckets[d.bucket as Bucket] = round2(g.buckets[d.bucket as Bucket] + Number(d.open_base));
    g.total = round2(g.total + Number(d.open_base));
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
});
const totals = computed(() => {
  const s = zero();
  for (const g of groups.value) for (const b of BUCKETS) s[b] = round2(s[b] + g.buckets[b]);
  return { buckets: s, total: round2(BUCKETS.reduce((n, b) => n + s[b], 0)) };
});
const chart = computed(() => BUCKETS.map((b) => ({ label: t(`aging.buckets.${b}`), value: Math.max(0, totals.value.buckets[b]) })));

const expanded = ref(new Set<number>());
function toggle(id: number) {
  const next = new Set(expanded.value);
  if (!next.delete(id)) next.add(id);
  expanded.value = next;
}
const docLink = (d: Doc) =>
  d.doc_type === "payment"
    ? `${side.value === "receivable" ? "/sales/receipts" : "/purchases/payments"}?id=${d.doc_id}`
    : `${d.doc_type.startsWith("sales") ? "/sales/invoices" : "/purchases/bills"}?id=${d.doc_id}`;
const kindLabel = (k: string) => (k === "payment" ? t("aging.advance") : t(`invoices.kinds.${k}`));
const exportRows = () =>
  (query.data.value ?? []).map((d) => ({
    [t("common.partner")]: d.partner, [t("invoices.docNo")]: d.doc_no, [t("aging.kind")]: kindLabel(d.doc_type),
    [t("common.date")]: d.invoice_date, [t("invoices.dueDate")]: d.due_date, [t("common.currency")]: d.currency,
    [t("invoices.open")]: d.open_amount, [t("aging.openBase")]: d.open_base, [t("aging.daysOverdue")]: d.days_overdue, [t("aging.bucket")]: t(`aging.buckets.${d.bucket}`),
  }));
</script>

<template>
  <div class="space-y-5">
    <TabBar v-model="side" :tabs="tabs" />
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t(`aging.title.${side}`) }}</h2>
      <label class="flex items-center gap-2 text-sm">
        <span class="text-muted-foreground">{{ t("aging.asOf") }}</span>
        <input v-model="asOf" type="date" required :class="[FIELD_CLASS, 'w-40']" />
      </label>
      <ExportMenu :name="`aging-${side}`" :title="`${t(`aging.title.${side}`)} · ${formatDate(asOf)}`" :rows="exportRows" :disabled="!query.data.value?.length" />
    </div>

    <LoadingState v-if="query.isPending.value" />
    <EmptyState v-else-if="query.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="query.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!groups.length" :title="t('aging.empty')" />
    <template v-else>
      <section class="bg-card rounded-xl border p-4">
        <h3 class="mb-3 text-sm font-semibold">{{ t("aging.chart") }}</h3>
        <BarChart :rows="chart" :format="(n: number) => formatMoney(n)" />
      </section>

      <div class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr class="[&>th]:px-3 [&>th]:py-2 [&>th]:font-medium [&>th]:whitespace-nowrap">
              <th>{{ t("common.partner") }}</th>
              <th v-for="b in BUCKETS" :key="b" class="text-right">{{ t(`aging.buckets.${b}`) }}</th>
              <th class="text-right">{{ t("common.total") }}</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="g in groups" :key="g.partnerId">
              <tr class="hover:bg-secondary/40 cursor-pointer border-b [&>td]:px-3 [&>td]:py-2" :aria-expanded="expanded.has(g.partnerId)" @click="toggle(g.partnerId)">
                <td>
                  <span class="flex items-center gap-1.5 font-medium">
                    <ChevronRight class="text-muted-foreground size-4 shrink-0 transition-transform" :class="expanded.has(g.partnerId) && 'rotate-90'" />
                    {{ g.partner }}
                    <span class="text-muted-foreground text-xs font-normal">({{ g.docs.length }})</span>
                  </span>
                </td>
                <td v-for="b in BUCKETS" :key="b" class="text-right tabular-nums" :class="b !== 'current' && g.buckets[b] > 0 && 'text-rose-600'">{{ formatAmount(g.buckets[b]) }}</td>
                <td class="text-right font-semibold tabular-nums">{{ formatAmount(g.total) }}</td>
              </tr>
              <template v-if="expanded.has(g.partnerId)">
                <tr v-for="d in g.docs" :key="`${d.doc_type}-${d.doc_id}`" class="bg-secondary/30 border-b text-xs [&>td]:px-3 [&>td]:py-1.5">
                  <td class="sm:pl-9">
                    <RouterLink :to="docLink(d)" class="text-primary-text font-mono hover:underline">{{ d.doc_no }}</RouterLink>
                    <span class="text-muted-foreground block">
                      {{ kindLabel(d.doc_type) }} · {{ t("invoices.dueDate") }} {{ formatDate(d.due_date) }}<template v-if="d.days_overdue > 0"> · {{ t("aging.days", { n: d.days_overdue }) }}</template>
                      <template v-if="d.currency !== 'IDR'"> · {{ formatMoney(d.open_amount, d.currency) }}</template>
                    </span>
                  </td>
                  <td v-for="b in BUCKETS" :key="b" class="text-right tabular-nums">{{ d.bucket === b ? formatAmount(d.open_base) : "" }}</td>
                  <td class="text-right tabular-nums">{{ formatAmount(d.open_base) }}</td>
                </tr>
              </template>
            </template>
            <tr class="bg-secondary/50 font-semibold [&>td]:px-3 [&>td]:py-2">
              <td>{{ t("common.total") }}</td>
              <td v-for="b in BUCKETS" :key="b" class="text-right tabular-nums">{{ formatAmount(totals.buckets[b]) }}</td>
              <td class="text-right tabular-nums">{{ formatAmount(totals.total) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
