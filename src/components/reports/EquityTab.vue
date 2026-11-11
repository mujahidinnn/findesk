<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, isoDate, monthStart } from "@/lib/format";
import { balanceSheet, equityChanges, incomeStatement, type AmountRow, type BalanceRow } from "@/lib/statements";
import CheckLine from "./CheckLine.vue";
import ReportFrame from "./ReportFrame.vue";
import StatementTable from "./StatementTable.vue";
import { addDays, exportRows, type ReportRow } from "./reportRows";

const { t } = useI18n();
const from = ref(monthStart());
const to = ref(isoDate());
const hideZero = ref(true);
const opening = useRpcQuery("balance_sheet", () => ({ p_as_of: addDays(from.value, -1) }));
const closing = useRpcQuery("balance_sheet", () => ({ p_as_of: to.value }));
const income = useRpcQuery("income_statement", () => ({ p_from: from.value, p_to: to.value }));
const queries = [opening, closing, income];
const pending = computed(() => queries.some((q) => q.isPending.value));
const failed = computed(() => queries.some((q) => q.isError.value));

const named = (rows: BalanceRow[]) => rows.map((r) => (r.code === "CYE" ? { ...r, name: t("reports.bs.cye") } : r));
const report = computed(() => {
  if (!opening.data.value || !closing.data.value || !income.data.value) return null;
  const net = incomeStatement([income.data.value as AmountRow[]]).netIncome[0];
  const r = equityChanges(named(opening.data.value), named(closing.data.value), net, hideZero.value);
  return { ...r, diff: r.totals.closing - balanceSheet([closing.data.value]).equity[0] };
});
const period = computed(() => `${formatDate(from.value)} – ${formatDate(to.value)}`);
const columns = computed(() => [t("reports.eq.opening"), t("reports.eq.movement"), t("reports.eq.closing")]);
const rows = computed<ReportRow[]>(() => {
  const r = report.value;
  if (!r) return [];
  return [
    ...r.lines.map((l): ReportRow => ({ key: l.key, kind: "account", label: l.name, code: l.code === "CYE" ? undefined : l.code, accountId: l.accountId, depth: 0, cells: [l.opening, l.movement, l.closing] })),
    { key: "total", kind: "grand", label: t("reports.eq.total"), depth: 0, cells: [r.totals.opening, r.totals.movement, r.totals.closing] },
    { key: "explain", kind: "section", label: t("reports.eq.explain") },
    { key: "ni", kind: "account", label: t("reports.eq.netIncome"), depth: 0, cells: [null, r.netIncome, null] },
    { key: "other", kind: "account", label: t("reports.eq.other"), depth: 0, cells: [null, r.other, null] },
    { key: "movement", kind: "total", label: t("reports.eq.totalMovement"), depth: 0, cells: [null, r.totals.movement, null] },
  ];
});
const exportFn = () => exportRows(rows.value, columns.value, t("reports.account"), t("common.code"));
</script>

<template>
  <ReportFrame
    :title="t('reports.tabs.equity')"
    :period="period"
    export-name="perubahan-ekuitas"
    :rows="exportFn"
    :pending="pending"
    :failed="failed"
    @retry="queries.forEach((q) => q.refetch())"
  >
    <template #controls>
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <label class="flex items-center gap-2 text-sm"><input v-model="hideZero" type="checkbox" class="accent-primary size-4" /> {{ t("reports.hideZero") }}</label>
    </template>
    <StatementTable :rows="rows" :columns="columns" />
    <CheckLine v-if="report" :label="t('reports.eq.check')" :diff="report.diff" />
  </ReportFrame>
</template>
