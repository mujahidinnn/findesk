<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { useI18n } from "vue-i18n";
import { ArrowLeftRight, Landmark, ListChecks, Scale, TrendingUp } from "@lucide/vue";
import TabBar from "@/components/common/TabBar.vue";
import BalanceSheetTab from "@/components/reports/BalanceSheetTab.vue";
import CashFlowTab from "@/components/reports/CashFlowTab.vue";
import EquityTab from "@/components/reports/EquityTab.vue";
import IncomeStatementTab from "@/components/reports/IncomeStatementTab.vue";
import TrialBalanceTab from "@/components/reports/TrialBalanceTab.vue";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const TABS = ["balance", "income", "cashflow", "trial", "equity"] as const;
const ICONS = { balance: Scale, income: TrendingUp, cashflow: ArrowLeftRight, trial: ListChecks, equity: Landmark };
const tab = useTabParam(() => TABS);
const tabs = computed(() => TABS.map((key) => ({ key, label: t(`reports.tabs.${key}`), icon: ICONS[key] })));

onMounted(() => document.documentElement.classList.add("report-print"));
onUnmounted(() => document.documentElement.classList.remove("report-print"));
</script>

<template>
  <div class="space-y-6">
    <TabBar v-model="tab" :tabs="tabs" class="print:hidden" />
    <BalanceSheetTab v-if="tab === 'balance'" />
    <IncomeStatementTab v-else-if="tab === 'income'" />
    <CashFlowTab v-else-if="tab === 'cashflow'" />
    <TrialBalanceTab v-else-if="tab === 'trial'" />
    <EquityTab v-else />
  </div>
</template>

<style>
@media print {
  html.report-print body :not(:has(.report-print-area), .report-print-area, .report-print-area *) {
    display: none !important;
  }
  html.report-print,
  html.report-print body,
  html.report-print body :has(.report-print-area) {
    display: block !important;
    height: auto !important;
    overflow: visible !important;
    margin: 0 !important;
    padding: 0 !important;
    background: white !important;
  }
  html.report-print .report-print-area {
    color: black;
    font-size: 11px;
  }
  @page {
    size: A4 portrait;
    margin: 14mm;
  }
}
</style>
