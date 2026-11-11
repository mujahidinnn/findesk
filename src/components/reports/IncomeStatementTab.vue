<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import AppSelect from "@/components/common/AppSelect.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { Input } from "@/components/ui/input";
import { useSimpleOptions } from "@/composables/useLookups";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, isoDate, monthStart, round2 } from "@/lib/format";
import { incomeStatement, isZero, pctChange, type AmountRow, type Section } from "@/lib/statements";
import CheckLine from "./CheckLine.vue";
import ReportFrame from "./ReportFrame.vue";
import StatementTable from "./StatementTable.vue";
import { exportRows, groupRows, lastYear, pctLabel, type Cell, type ReportRow } from "./reportRows";

const { t } = useI18n();
const from = ref(monthStart());
const to = ref(isoDate());
const compare = ref(false);
const cFrom = ref(lastYear(from.value));
const cTo = ref(lastYear(to.value));
watch([from, to], ([f, e]) => ((cFrom.value = lastYear(f)), (cTo.value = lastYear(e))));
const costCenter = ref<number | null>(null);
const project = ref<number | null>(null);
const hideZero = ref(true);
const costCenters = useSimpleOptions("m_cost_centers").options;
const projects = useSimpleOptions("m_projects").options;

const args = (f: string, e: string) => ({ p_from: f, p_to: e, p_cost_center_id: costCenter.value ?? undefined, p_project_id: project.value ?? undefined });
const current = useRpcQuery("income_statement", () => args(from.value, to.value));
const previous = useRpcQuery("income_statement", () => (compare.value ? args(cFrom.value, cTo.value) : null));
const withCompare = computed(() => compare.value && !!previous.data.value);
const pending = computed(() => current.isPending.value || (compare.value && previous.isPending.value));
const failed = computed(() => current.isError.value || (compare.value && previous.isError.value));

const report = computed(() => {
  const now = current.data.value as AmountRow[] | undefined;
  if (!now) return null;
  return incomeStatement(withCompare.value ? [now, previous.data.value as AmountRow[]] : [now], hideZero.value);
});
const range = (f: string, e: string) => `${formatDate(f)} – ${formatDate(e)}`;
const columns = computed(() =>
  withCompare.value
    ? [range(from.value, to.value), t("reports.is.ofRevenue"), range(cFrom.value, cTo.value), t("reports.change"), "%"]
    : [range(from.value, to.value), t("reports.is.ofRevenue")],
);

const rows = computed<ReportRow[]>(() => {
  const r = report.value;
  if (!r) return [];
  const revenue = r.sections.revenue.total[0];
  const cells = (v: number[]): Cell[] => {
    const share = isZero(revenue) ? "" : pctLabel(round2((v[0] / revenue) * 100));
    return withCompare.value ? [v[0], share, v[1] ?? 0, round2(v[0] - (v[1] ?? 0)), pctLabel(pctChange(v[0], v[1] ?? 0))] : [v[0], share];
  };
  const totalOf = (name: string) => t("reports.totalOf", { name });
  const group = (key: keyof typeof r.sections) => {
    const label = t(`reports.is.${key}`);
    return groupRows(key, label, r.sections[key] as Section, cells, totalOf(label.toLowerCase()), totalOf, hideZero.value);
  };
  const line = (key: string, values: number[], kind: "total" | "grand" = "total"): ReportRow => ({ key, kind, label: t(`reports.is.${key}`), depth: 0, cells: cells(values) });
  return [
    ...group("revenue"),
    ...group("cogs"),
    line("grossProfit", r.grossProfit),
    ...group("opex"),
    line("operatingProfit", r.operatingProfit),
    ...group("otherIncome"),
    ...group("otherExpense"),
    line("profitBeforeTax", r.profitBeforeTax),
    ...group("tax"),
    line("netIncome", r.netIncome, "grand"),
  ];
});
const exportFn = () => exportRows(rows.value, columns.value, t("reports.account"), t("common.code"));
</script>

<template>
  <ReportFrame
    :title="t('reports.tabs.income')"
    :period="range(from, to)"
    export-name="laba-rugi"
    :rows="exportFn"
    :pending="pending"
    :failed="failed"
    @retry="(current.refetch(), previous.refetch())"
  >
    <template #controls>
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <AppSelect v-model="costCenter" :options="costCenters" :null-label="t('reports.allCostCenters')" class="w-44" :aria-label="t('common.costCenter')" />
      <AppSelect v-model="project" :options="projects" :null-label="t('reports.allProjects')" class="w-44" :aria-label="t('common.project')" />
      <label class="flex items-center gap-2 text-sm"><input v-model="compare" type="checkbox" class="accent-primary size-4" /> {{ t("reports.compareWith") }}</label>
      <template v-if="compare">
        <Input v-model="cFrom" type="date" class="h-9 w-40" :aria-label="t('period.from')" />
        <Input v-model="cTo" type="date" class="h-9 w-40" :aria-label="t('period.to')" />
      </template>
      <label class="flex items-center gap-2 text-sm"><input v-model="hideZero" type="checkbox" class="accent-primary size-4" /> {{ t("reports.hideZero") }}</label>
    </template>
    <StatementTable :rows="rows" :columns="columns" />
    <CheckLine v-if="report" :label="t('reports.is.check')" :diff="report.diff[0]" />
  </ReportFrame>
</template>
