<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { Info, Package, Truck, Users } from "@lucide/vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import PartnerDetail from "@/components/invoice/PartnerDetail.vue";
import { Button } from "@/components/ui/button";
import { useAccountOptions, useCurrencyOptions, useSimpleOptions, useTaxOptions } from "@/composables/useLookups";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const TABS = ["customers", "vendors", "items"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: TABS[0], label: t("partners.tabs.customers"), icon: Users },
  { key: TABS[1], label: t("partners.tabs.vendors"), icon: Truck },
  { key: TABS[2], label: t("partners.tabs.items"), icon: Package },
]);

const terms = useSimpleOptions("m_payment_terms");
const currencies = useCurrencyOptions();
const partnerFields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true, lockOnEdit: true },
  { key: "name", label: t("common.name"), required: true },
  { key: "city", label: t("partners.city") },
  { key: "phone", label: t("partners.phone") },
  { key: "email", label: t("partners.email"), hideInTable: true },
  { key: "contact_person", label: t("partners.contact"), hideInTable: true },
  { key: "npwp", label: t("partners.npwp"), pattern: "[0-9.\\-]{15,22}", hint: t("partners.npwpHint"), mono: true, hideInTable: true },
  { key: "term_id", label: t("invoices.term"), type: "select", options: terms.options.value },
  { key: "currency", label: t("common.currency"), type: "select", options: currencies.value, required: true, default: "IDR" },
  { key: "credit_limit", label: t("partners.creditLimit"), type: "money", default: 0, hint: t("partners.creditLimitHint"), hideInTable: tab.value !== "customers" },
  { key: "bank_name", label: t("partners.bankName"), hideInTable: true },
  { key: "bank_account_no", label: t("partners.bankAccountNo"), mono: true, hideInTable: true },
  { key: "bank_account_name", label: t("partners.bankAccountName"), hideInTable: true },
  { key: "address", label: t("partners.address"), type: "textarea", hideInTable: true },
  { key: "note", label: t("common.note"), type: "textarea", hideInTable: true },
  { key: "is_customer", label: t("partners.isCustomer"), type: "boolean", default: tab.value === "customers", hideInTable: tab.value === "customers" },
  { key: "is_vendor", label: t("partners.isVendor"), type: "boolean", default: tab.value === "vendors", hideInTable: tab.value === "vendors" },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);

const revenue = useAccountOptions({ types: ["revenue"] });
const expense = useAccountOptions({ types: ["expense", "asset"], exclude: ["receivable", "bank", "cash", "accumulated_depreciation"] });
const inventory = useAccountOptions({ subtypes: ["inventory"] });
const cogs = useAccountOptions({ subtypes: ["cogs"] });
const vat = useTaxOptions("vat");
const wht = useTaxOptions("wht");
const itemFields = computed<CrudField[]>(() => [
  { key: "code", label: t("common.code"), required: true, upper: true, mono: true, lockOnEdit: true },
  { key: "name", label: t("common.name"), required: true },
  { key: "kind", label: t("partners.itemKind"), type: "select", required: true, default: "service", options: [
    { value: "service", label: t("partners.kinds.service") }, { value: "goods", label: t("partners.kinds.goods") },
  ] },
  { key: "unit", label: t("partners.unit"), required: true, default: "pcs" },
  { key: "sales_price", label: t("partners.salesPrice"), type: "money", default: 0 },
  { key: "purchase_price", label: t("partners.purchasePrice"), type: "money", default: 0 },
  { key: "unit_cost", label: t("partners.unitCost"), type: "money", default: 0, hint: t("partners.unitCostHint"), hideInTable: true },
  { key: "revenue_account_id", label: t("partners.revenueAccount"), type: "select", options: revenue.options.value, hideInTable: true },
  { key: "expense_account_id", label: t("partners.expenseAccount"), type: "select", options: expense.options.value, hideInTable: true },
  { key: "inventory_account_id", label: t("partners.inventoryAccount"), type: "select", options: inventory.options.value, hint: t("partners.inventoryHint"), hideInTable: true },
  { key: "cogs_account_id", label: t("partners.cogsAccount"), type: "select", options: cogs.options.value, hideInTable: true },
  { key: "sales_tax_id", label: t("partners.salesTax"), type: "select", options: vat.options.value, hideInTable: true },
  { key: "purchase_tax_id", label: t("partners.purchaseTax"), type: "select", options: vat.options.value, hideInTable: true },
  { key: "wht_tax_id", label: t("partners.whtTax"), type: "select", options: wht.options.value, hideInTable: true },
  { key: "is_active", label: t("common.active"), type: "boolean", default: true },
]);

const detailId = computed({
  get: () => Number(route.query.id) || null,
  set: (v) => void router.replace({ query: { ...route.query, id: v ?? undefined } }),
});
</script>

<template>
  <div class="space-y-5">
    <TabBar v-model="tab" :tabs="tabs" />
    <CrudTable
      v-if="tab === 'customers' || tab === 'vendors'"
      :key="tab"
      table="m_partners"
      feature="partner"
      :title="t(`partners.tabs.${tab}`)"
      :fields="partnerFields"
      :filter="tab === 'customers' ? { is_customer: true } : { is_vendor: true }"
      order="name"
      :search-keys="['code', 'name', 'city', 'npwp', 'contact_person']"
    >
      <template #row-actions="{ row }">
        <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="detailId = row.id"><Info /></Button>
      </template>
    </CrudTable>
    <CrudTable v-else-if="tab === 'items'" table="m_items" feature="partner" :title="t('partners.tabs.items')" :fields="itemFields" order="code" />
    <PartnerDetail v-model:id="detailId" />
  </div>
</template>
