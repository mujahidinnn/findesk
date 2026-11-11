<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { CalendarClock, Info, Layers, Package } from "@lucide/vue";
import AssetRegister from "@/components/asset/AssetRegister.vue";
import DepreciationRuns from "@/components/asset/DepreciationRuns.vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import { useAccountOptions } from "@/composables/useLookups";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const TABS = ["register", "depreciation", "categories"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: "register" as const, label: t("assets.tabs.register"), icon: Package },
  { key: "depreciation" as const, label: t("assets.tabs.depreciation"), icon: CalendarClock },
  { key: "categories" as const, label: t("assets.tabs.categories"), icon: Layers },
]);

const assetAccounts = useAccountOptions({ types: ["asset"] });
const expenseAccounts = useAccountOptions({ types: ["expense"] });
const categoryFields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true },
  { key: "name", label: t("common.name"), required: true },
  {
    key: "method",
    label: t("assets.method"),
    type: "select",
    required: true,
    default: "straight_line",
    options: ["straight_line", "declining", "none"].map((m) => ({ value: m, label: t(`assets.methods.${m}`) })),
  },
  { key: "useful_life_months", label: t("assets.lifeMonths"), type: "number", step: "1", required: true, default: 48, hint: t("assets.lifeHint") },
  { key: "asset_account_id", label: t("assets.assetAccount"), type: "select", required: true, options: assetAccounts.options.value, hideInTable: true },
  { key: "accum_account_id", label: t("assets.accumAccount"), type: "select", options: assetAccounts.options.value, hideInTable: true },
  { key: "expense_account_id", label: t("assets.expenseAccount"), type: "select", options: expenseAccounts.options.value, hideInTable: true },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);
</script>

<template>
  <div class="space-y-4">
    <TabBar v-model="tab" :tabs="tabs" />
    <AssetRegister v-if="tab === 'register'" />
    <DepreciationRuns v-else-if="tab === 'depreciation'" />
    <template v-else>
      <div class="bg-primary-soft text-primary-text border-brand-200 dark:border-brand-500/30 flex gap-2 rounded-xl border p-3 text-sm">
        <Info class="mt-0.5 size-4 shrink-0" />
        <p>{{ t("assets.fiscalHint") }}</p>
      </div>
      <CrudTable table="m_asset_categories" feature="asset" :title="t('assets.tabs.categories')" :fields="categoryFields" order="code" />
    </template>
  </div>
</template>
