<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { FileMinus, FileText } from "@lucide/vue";
import TabBar from "@/components/common/TabBar.vue";
import InvoiceList from "@/components/invoice/InvoiceList.vue";
import InvoiceSummary from "@/components/invoice/InvoiceSummary.vue";
import { useTabParam } from "@/composables/useTabParam";

const { t } = useI18n();
const TABS = ["purchase_bill", "purchase_debit"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: TABS[0], label: t("invoices.tabs.purchase_bill"), icon: FileText },
  { key: TABS[1], label: t("invoices.tabs.purchase_debit"), icon: FileMinus },
]);
</script>

<template>
  <div class="space-y-5">
    <InvoiceSummary side="purchase" />
    <TabBar v-model="tab" :tabs="tabs" />
    <InvoiceList v-if="tab" :key="tab" :doc-type="tab" />
  </div>
</template>
