<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useI18n } from "vue-i18n";
import { ArrowLeftRight, ArrowUpDown, Landmark, TrendingUp } from "@lucide/vue";
import BankAccounts from "@/components/cash/BankAccounts.vue";
import BankTransfers from "@/components/cash/BankTransfers.vue";
import CashTxns from "@/components/cash/CashTxns.vue";
import LineChart from "@/components/charts/LineChart.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import TabBar from "@/components/common/TabBar.vue";
import { useCurrencyOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { useSettings } from "@/composables/useSettings";
import { useTabParam } from "@/composables/useTabParam";
import { formatRate } from "@/lib/format";

const { t } = useI18n();
const TABS = ["accounts", "txns", "transfers", "rates"] as const;
const tab = useTabParam(() => TABS);
if (useRoute().query.id && !useRoute().query.tab) tab.value = "txns";
const ICONS = { accounts: Landmark, txns: ArrowUpDown, transfers: ArrowLeftRight, rates: TrendingUp };
const tabs = computed(() => TABS.map((key) => ({ key, label: t(`cash.tabs.${key}`), icon: ICONS[key] })));

const settings = useSettings();
const base = computed(() => settings.data.value?.base_currency ?? "IDR");

const currencies = useCurrencyOptions();
const foreignCurrencies = computed(() => currencies.value.filter((c) => c.value !== base.value));
const rateFields = computed<CrudField[]>(() => [
  { key: "currency", label: t("common.currency"), type: "select", required: true, options: foreignCurrencies.value, lockOnEdit: true },
  { key: "rate_date", label: t("common.date"), type: "date", required: true, lockOnEdit: true },
  { key: "rate", label: t("cash.rates.rate", { base: base.value }), type: "number", step: "0.000001", required: true },
]);
const chartCurrency = ref("USD");
const history = useMasterRows("m_fx_rates", { filter: () => ({ currency: chartCurrency.value }), order: "rate_date" });
const points = computed(() => (history.data.value ?? []).map((r) => ({ date: String(r.rate_date), value: Number(r.rate) })));
</script>

<template>
  <div class="space-y-4">
    <TabBar v-model="tab" :tabs="tabs" />
    <BankAccounts v-if="tab === 'accounts'" :base="base" />
    <CashTxns v-else-if="tab === 'txns'" :base="base" />
    <BankTransfers v-else-if="tab === 'transfers'" :base="base" />
    <template v-else>
      <section class="bg-card space-y-3 rounded-xl border p-4">
        <div class="toolbar">
          <h2 class="mr-auto font-semibold">{{ t("cash.rates.history", { currency: chartCurrency }) }}</h2>
          <AppSelect :model-value="chartCurrency" :options="foreignCurrencies" class="w-44" :aria-label="t('common.currency')" @update:model-value="(v) => v && (chartCurrency = v)" />
        </div>
        <LineChart v-if="points.length > 1" :points="points" :format="formatRate" :zero-based="false" />
        <EmptyState v-else compact :title="t('common.empty')" />
      </section>
      <CrudTable table="m_fx_rates" feature="cash-bank" :title="t('cash.tabs.rates')" :fields="rateFields" order="rate_date" descending />
    </template>
  </div>
</template>
