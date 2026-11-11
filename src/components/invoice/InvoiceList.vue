<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { Plus } from "@lucide/vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import InvoiceDetail from "@/components/invoice/InvoiceDetail.vue";
import InvoiceEditor from "@/components/invoice/InvoiceEditor.vue";
import { docLabel, featureOf, nameOf, openOf, sideOf, type DocType } from "@/components/invoice/docTypes";
import { Button } from "@/components/ui/button";
import { useMasterRows } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { formatDate, formatMoney } from "@/lib/format";

const props = defineProps<{ docType: DocType }>();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { can } = usePermissions();
const feature = computed(() => featureOf(props.docType));
const side = computed(() => sideOf(props.docType));

const rows = useMasterRows("t_invoices", {
  filter: () => ({ doc_type: props.docType }),
  columns: "id, doc_no, doc_type, invoice_date, due_date, reference, currency, total, paid_amount, status, partner_id, partner:m_partners(name, code)",
  order: "invoice_date",
  descending: true,
});

const detailId = computed({
  get: () => Number(route.query.id) || null,
  set: (v) => void router.replace({ query: { ...route.query, id: v ?? undefined } }),
});
const editorOpen = ref(false);
const editId = ref<number | null>(null);
const editType = ref<DocType>(props.docType);
function openEditor(id: number | null, docType: DocType = props.docType) {
  editId.value = id;
  editType.value = docType;
  detailId.value = null;
  editorOpen.value = true;
}
const exportRows = () =>
  (rows.data.value ?? []).map((r) => ({
    [t("invoices.docNo")]: docLabel(r), [t("common.date")]: r.invoice_date, [t("invoices.dueDate")]: r.due_date,
    [t("common.partner")]: nameOf(r.partner), [t("common.reference")]: r.reference, [t("common.currency")]: r.currency,
    [t("common.total")]: r.total, [t("invoices.open")]: openOf(r), [t("common.status")]: t(`status.${r.status}`),
  }));
</script>

<template>
  <DocTable
    :title="t(`invoices.lists.${docType}`)"
    :columns="[t('invoices.docNo'), t('common.date'), t('invoices.dueDate'), t(side === 'sales' ? 'invoices.customer' : 'invoices.vendor'), t('common.reference'), t('common.total'), t('invoices.open'), t('common.status')]"
    :rows="rows.data.value ?? []"
    :pending="rows.isPending.value"
    :failed="rows.isError.value"
    :status-label="(s: string) => t(`status.${s}`)"
    @retry="rows.refetch()"
  >
    <template #toolbar>
      <ExportMenu :name="docType" :title="t(`invoices.lists.${docType}`)" :rows="exportRows" />
      <Button v-if="can(feature, 'create')" size="sm" @click="openEditor(null)"><Plus /> {{ t(`invoices.new.${docType}`) }}</Button>
    </template>
    <template #row="{ row }">
      <td>
        <button type="button" class="text-primary-text font-mono text-xs hover:underline" @click="detailId = row.id">{{ docLabel(row) }}</button>
      </td>
      <td class="whitespace-nowrap">{{ formatDate(String(row.invoice_date)) }}</td>
      <td class="whitespace-nowrap">{{ formatDate(row.due_date as string | null) }}</td>
      <td>{{ nameOf(row.partner) }}</td>
      <td>{{ row.reference ?? "-" }}</td>
      <td class="text-right tabular-nums">{{ formatMoney(row.total, String(row.currency)) }}</td>
      <td class="text-right tabular-nums">{{ row.status === "posted" ? formatMoney(openOf(row), String(row.currency)) : "-" }}</td>
      <td><DocStatus :status="String(row.status)" :paid="row.paid_amount" :total="row.total" :due="row.due_date as string" /></td>
    </template>
  </DocTable>

  <InvoiceDetail v-model:id="detailId" @edit="openEditor" />
  <InvoiceEditor :id="editId" v-model:open="editorOpen" :doc-type="editType" @saved="(id) => (detailId = id)" />
</template>
