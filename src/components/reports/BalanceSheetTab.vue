<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Input } from "@/components/ui/input";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, isoDate } from "@/lib/format";
import { balanceSheet, type BalanceRow } from "@/lib/statements";
import CheckLine from "./CheckLine.vue";
import ReportFrame from "./ReportFrame.vue";
import StatementTable from "./StatementTable.vue";
import { compareCells, exportRows, groupRows, lastYear, type ReportRow } from "./reportRows";

const { t } = useI18n();
const asOf = ref(isoDate());
const compare = ref(false);
const compareOf = ref(lastYear(isoDate()));
const hideZero = ref(true);

const current = useRpcQuery("balance_sheet", () => ({ p_as_of: asOf.value }));
const previous = useRpcQuery("balance_sheet", () => (compare.value ? { p_as_of: compareOf.value } : null));
const withCompare = computed(() => compare.value && !!previous.data.value);
const pending = computed(() => current.isPending.value || (compare.value && previous.isPending.value));
const failed = computed(() => current.isError.value || (compare.value && previous.isError.value));

const named = (rows: BalanceRow[] | undefined) => (rows ?? []).map((r) => (r.code === "CYE" ? { ...r, name: t("reports.bs.cye") } : r));
const report = computed(() =>
  current.data.value ? balanceSheet(withCompare.value ? [named(current.data.value), named(previous.data.value)] : [named(current.data.value)], hideZero.value) : null,
);
const columns = computed(() =>
  withCompare.value ? [formatDate(asOf.value), formatDate(compareOf.value), t("reports.change"), "%"] : [formatDate(asOf.value)],
);

const rows = computed<ReportRow[]>(() => {
  const r = report.value;
  if (!r) return [];
  const cells = (v: number[]) => compareCells(v, withCompare.value);
  const totalOf = (name: string) => t("reports.totalOf", { name });
  const group = (key: string) => {
    const label = t(`reports.bs.${key}`);
    return groupRows(key, label, r.sections.find((s) => s.key === key)!, cells, totalOf(label.toLowerCase()), totalOf, hideZero.value);
  };
  return [
    { key: "assets", kind: "section", label: t("reports.bs.assets") },
    ...group("currentAssets"),
    ...group("nonCurrentAssets"),
    { key: "assets:total", kind: "grand", label: t("reports.bs.totalAssets"), depth: 0, cells: cells(r.assets) },
    { key: "le", kind: "section", label: t("reports.bs.liabilitiesEquity") },
    ...group("currentLiabilities"),
    ...group("longTermLiabilities"),
    { key: "liabilities:total", kind: "total", label: t("reports.bs.totalLiabilities"), depth: 0, cells: cells(r.liabilities) },
    ...group("equity"),
    { key: "le:total", kind: "grand", label: t("reports.bs.totalLiabilitiesEquity"), depth: 0, cells: cells(r.liabilitiesEquity) },
  ];
});
const exportFn = () => exportRows(rows.value, columns.value, t("reports.account"), t("common.code"));
</script>

<template>
  <ReportFrame
    :title="t('reports.tabs.balance')"
    :period="t('reports.asOf', { date: formatDate(asOf) })"
    export-name="neraca"
    :rows="exportFn"
    :pending="pending"
    :failed="failed"
    @retry="(current.refetch(), previous.refetch())"
  >
    <template #controls>
      <label class="flex items-center gap-2 text-sm">{{ t("reports.asOfLabel") }} <Input v-model="asOf" type="date" class="h-9 w-40" required /></label>
      <label class="flex items-center gap-2 text-sm"><input v-model="compare" type="checkbox" class="accent-primary size-4" /> {{ t("reports.compareWith") }}</label>
      <Input v-if="compare" v-model="compareOf" type="date" class="h-9 w-40" :aria-label="t('reports.compareWith')" />
      <label class="flex items-center gap-2 text-sm"><input v-model="hideZero" type="checkbox" class="accent-primary size-4" /> {{ t("reports.hideZero") }}</label>
    </template>
    <StatementTable :rows="rows" :columns="columns" />
    <template v-if="report">
      <CheckLine :label="t('reports.bs.check', { date: formatDate(asOf) })" :diff="report.diff[0]" />
      <CheckLine v-if="withCompare" :label="t('reports.bs.check', { date: formatDate(compareOf) })" :diff="report.diff[1]" />
    </template>
  </ReportFrame>
</template>
