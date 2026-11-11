<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Percent, Receipt, Scissors } from "@lucide/vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import VatReport from "@/components/tax/VatReport.vue";
import WhtReport from "@/components/tax/WhtReport.vue";
import { useAccountOptions } from "@/composables/useLookups";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const TABS = ["vat", "wht", "codes"] as const;
const tab = useTabParam(() => TABS);
const ICONS = { vat: Receipt, wht: Scissors, codes: Percent };
const tabs = computed(() => TABS.map((key) => ({ key, label: t(`tax.tabs.${key}`), icon: ICONS[key] })));

const taxAccounts = useAccountOptions({ subtypes: ["tax_payable", "tax_prepaid"] });
const WHT_TYPES = ["pph21", "pph22", "pph23", "pph4a2", "pph15", "pph26"] as const;
const fields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true },
  { key: "name", label: t("common.name"), required: true },
  { key: "kind", label: t("tax.codes.kind"), type: "select", required: true, default: "vat", options: [{ value: "vat", label: t("tax.codes.kinds.vat") }, { value: "wht", label: t("tax.codes.kinds.wht") }] },
  { key: "wht_type", label: t("tax.wht.type"), type: "select", options: WHT_TYPES.map((w) => ({ value: w, label: t(`tax.whtTypes.${w}`) })), hint: t("tax.codes.whtTypeHint") },
  { key: "rate", label: t("tax.codes.rate"), type: "number", step: "0.0001", required: true },
  { key: "dpp_factor", label: t("tax.codes.dppFactor"), type: "number", step: "0.0000000001", default: 1, required: true, hint: t("tax.codes.dppHint") },
  { key: "sales_account_id", label: t("tax.codes.salesAccount"), type: "select", required: true, options: taxAccounts.options.value, hideInTable: true, hint: t("tax.codes.salesHint") },
  { key: "purchase_account_id", label: t("tax.codes.purchaseAccount"), type: "select", required: true, options: taxAccounts.options.value, hideInTable: true, hint: t("tax.codes.purchaseHint") },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);
</script>

<template>
  <div class="space-y-4">
    <TabBar v-model="tab" :tabs="tabs" />
    <VatReport v-if="tab === 'vat'" />
    <WhtReport v-else-if="tab === 'wht'" />
    <CrudTable v-else table="m_taxes" feature="tax" :title="t('tax.tabs.codes')" :fields="fields" order="code" />
  </div>
</template>
