<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, isoDate, monthStart, round2 } from "@/lib/format";
import { cashFlow } from "@/lib/statements";
import CheckLine from "./CheckLine.vue";
import ReportFrame from "./ReportFrame.vue";
import StatementTable from "./StatementTable.vue";
import { exportRows, type ReportRow } from "./reportRows";

const { t } = useI18n();
const from = ref(monthStart());
const to = ref(isoDate());
const q = useRpcQuery("cash_flow", () => ({ p_from: from.value, p_to: to.value }));
const report = computed(() => (q.data.value ? cashFlow(q.data.value) : null));
const period = computed(() => `${formatDate(from.value)} – ${formatDate(to.value)}`);
const columns = computed(() => [period.value]);

const rows = computed<ReportRow[]>(() => {
  const r = report.value;
  if (!r) return [];
  return [
    ...r.sections.flatMap((s): ReportRow[] => [
      { key: s.key, kind: "group", label: t(`reports.cf.${s.key}`), depth: 0 },
      ...s.lines.map((l): ReportRow =>
        l.code === "NI"
          ? { key: "NI", kind: "account", label: t("reports.cf.netIncome"), depth: 1, cells: [l.amount] }
          : { key: `${s.key}:${l.code}`, kind: "account", label: t("reports.cf.changeIn", { name: l.name }), code: l.code, accountId: l.account_id, depth: 1, cells: [l.amount] },
      ),
      ...(s.lines.length ? [] : [{ key: `${s.key}:none`, kind: "account" as const, label: t("reports.cf.none"), depth: 1, cells: [0] }]),
      { key: `${s.key}:total`, kind: "total", label: t(`reports.cf.${s.key}Total`), depth: 0, cells: [s.total] },
    ]),
    { key: "net", kind: "grand", label: t("reports.cf.netChange"), depth: 0, cells: [r.netChange] },
    { key: "opening", kind: "account", label: t("reports.cf.opening"), depth: 0, cells: [r.opening] },
    { key: "closing", kind: "total", label: t("reports.cf.closing"), depth: 0, cells: [round2(r.opening + r.netChange)] },
  ];
});
const exportFn = () => exportRows(rows.value, columns.value, t("reports.account"), t("common.code"));
</script>

<template>
  <ReportFrame :title="t('reports.tabs.cashflow')" :period="period" export-name="arus-kas" :rows="exportFn" :pending="q.isPending.value" :failed="q.isError.value" @retry="q.refetch()">
    <template #controls>
      <PeriodFilter v-model:from="from" v-model:to="to" />
    </template>
    <StatementTable :rows="rows" :columns="columns" />
    <p class="text-muted-foreground mt-2 text-xs">{{ t("reports.cf.hint") }}</p>
    <CheckLine v-if="report" :label="t('reports.cf.check', { amount: report.closing.toLocaleString('id-ID') })" :diff="report.diff" />
  </ReportFrame>
</template>
