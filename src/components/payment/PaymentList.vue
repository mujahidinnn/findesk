<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { Plus } from "@lucide/vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import { docLabel, featureOf, nameOf, type Direction } from "@/components/invoice/docTypes";
import PaymentDetail from "@/components/payment/PaymentDetail.vue";
import PaymentEditor from "@/components/payment/PaymentEditor.vue";
import { Button } from "@/components/ui/button";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { formatDate, formatMoney, round2 } from "@/lib/format";

const props = defineProps<{ direction: Direction }>();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { can } = usePermissions();
const feature = computed(() => featureOf(props.direction));

const rows = useMasterRows("t_payments", {
  filter: () => ({ direction: props.direction }),
  columns: "*, partner:m_partners(name, code), bank:m_bank_accounts(name)",
  order: "payment_date",
  descending: true,
});
const unallocated = (r: MasterRow) => round2(Number(r.amount) + Number(r.wht_amount) - Number(r.allocated_amount));

const detailId = computed({
  get: () => Number(route.query.id) || null,
  set: (v) => void router.replace({ query: { ...route.query, id: v ?? undefined } }),
});
const editorOpen = ref(false);
const editId = ref<number | null>(null);
function openEditor(id: number | null) {
  editId.value = id;
  detailId.value = null;
  editorOpen.value = true;
}
const exportRows = () =>
  (rows.data.value ?? []).map((r) => ({
    [t("payments.docNo")]: docLabel(r), [t("common.date")]: r.payment_date, [t("common.partner")]: nameOf(r.partner), [t("payments.bankAccount")]: nameOf(r.bank),
    [t("common.currency")]: r.currency, [t("common.amount")]: r.amount, [t("payments.whtAmount")]: r.wht_amount, [t("payments.allocated")]: r.allocated_amount,
    [t("common.reference")]: r.reference, [t("common.status")]: t(`status.${r.status}`),
  }));
</script>

<template>
  <DocTable
    :title="t(`payments.lists.${direction}`)"
    :columns="[t('payments.docNo'), t('common.date'), t('common.partner'), t('payments.bankAccount'), t('common.amount'), t('payments.unallocated'), t('common.status')]"
    :rows="rows.data.value ?? []"
    :pending="rows.isPending.value"
    :failed="rows.isError.value"
    :status-label="(s: string) => t(`status.${s}`)"
    @retry="rows.refetch()"
  >
    <template #toolbar>
      <ExportMenu :name="`payments-${direction}`" :title="t(`payments.lists.${direction}`)" :rows="exportRows" />
      <Button v-if="can(feature, 'create')" size="sm" @click="openEditor(null)"><Plus /> {{ t(`payments.new.${direction}`) }}</Button>
    </template>
    <template #row="{ row }">
      <td>
        <button type="button" class="text-primary-text font-mono text-xs hover:underline" @click="detailId = row.id">{{ docLabel(row) }}</button>
      </td>
      <td class="whitespace-nowrap">{{ formatDate(String(row.payment_date)) }}</td>
      <td>{{ nameOf(row.partner) }}</td>
      <td>{{ nameOf(row.bank) }}</td>
      <td class="text-right tabular-nums">{{ formatMoney(row.amount, String(row.currency)) }}</td>
      <td class="text-right tabular-nums">
        {{ row.status === "posted" && unallocated(row) > 0 ? formatMoney(unallocated(row), String(row.currency)) : "-" }}
      </td>
      <td><DocStatus :status="String(row.status)" /></td>
    </template>
  </DocTable>

  <PaymentDetail v-model:id="detailId" @edit="openEditor" />
  <PaymentEditor :id="editId" v-model:open="editorOpen" :direction="direction" @saved="(id) => (detailId = id)" />
</template>
