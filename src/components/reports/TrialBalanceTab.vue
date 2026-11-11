<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import AppSelect from "@/components/common/AppSelect.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { useSimpleOptions } from "@/composables/useLookups";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, isoDate, monthStart } from "@/lib/format";
import { trialBalance, type TrialRow } from "@/lib/statements";
import CheckLine from "./CheckLine.vue";
import ReportFrame from "./ReportFrame.vue";
import StatementTable from "./StatementTable.vue";
import { exportRows, type ReportRow } from "./reportRows";

const { t } = useI18n();
const from = ref(monthStart());
const to = ref(isoDate());
const costCenter = ref<number | null>(null);
const project = ref<number | null>(null);
const excludeClosing = ref(false);
const hideZero = ref(true);
const costCenters = useSimpleOptions("m_cost_centers").options;
const projects = useSimpleOptions("m_projects").options;

const q = useRpcQuery("trial_balance", () => ({
  p_from: from.value, p_to: to.value, p_cost_center_id: costCenter.value ?? undefined, p_project_id: project.value ?? undefined,
  p_exclude_closing: excludeClosing.value,
}));
const report = computed(() => (q.data.value ? trialBalance(q.data.value as TrialRow[], hideZero.value) : null));
const period = computed(() => `${formatDate(from.value)} – ${formatDate(to.value)}`);
const columns = computed(() => [t("reports.tb.opening"), t("common.debit"), t("common.credit"), t("reports.tb.closing")]);
const rows = computed<ReportRow[]>(() => {
  const r = report.value;
  if (!r) return [];
  return [
    ...r.lines.map((l): ReportRow => ({ key: String(l.account_id), kind: "account", label: l.name, code: l.code, accountId: l.account_id, depth: 0, cells: [l.opening, l.debit, l.credit, l.closing] })),
    { key: "total", kind: "grand", label: t("common.total"), depth: 0, cells: [r.totals.opening, r.totals.debit, r.totals.credit, r.totals.closing] },
  ];
});
const exportFn = () => exportRows(rows.value, columns.value, t("reports.account"), t("common.code"));
</script>

<template>
  <ReportFrame :title="t('reports.tabs.trial')" :period="period" export-name="neraca-saldo" :rows="exportFn" :pending="q.isPending.value" :failed="q.isError.value" @retry="q.refetch()">
    <template #controls>
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <AppSelect v-model="costCenter" :options="costCenters" :null-label="t('reports.allCostCenters')" class="w-44" :aria-label="t('common.costCenter')" />
      <AppSelect v-model="project" :options="projects" :null-label="t('reports.allProjects')" class="w-44" :aria-label="t('common.project')" />
      <label class="flex items-center gap-2 text-sm"><input v-model="excludeClosing" type="checkbox" class="accent-primary size-4" /> {{ t("reports.tb.excludeClosing") }}</label>
      <label class="flex items-center gap-2 text-sm"><input v-model="hideZero" type="checkbox" class="accent-primary size-4" /> {{ t("reports.hideZero") }}</label>
    </template>
    <StatementTable :rows="rows" :columns="columns" />
    <p class="text-muted-foreground mt-2 text-xs">{{ t("reports.tb.hint") }}</p>
    <template v-if="report">
      <CheckLine :label="t('reports.tb.check')" :diff="report.totals.debit - report.totals.credit" />
      <CheckLine :label="t('reports.tb.checkClosing')" :diff="report.totals.closing" />
    </template>
  </ReportFrame>
</template>
