<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { FileText, RefreshCw } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import { openReceipt } from "@/components/expense/receipt";
import { useMasterRows, type MasterRow, type MasterTable } from "@/composables/useMasterRows";
import { useServerError } from "@/composables/useServerError";
import { formatAmount, formatDate, formatQty } from "@/lib/format";

const props = defineProps<{ kind: string; id: number }>();
const { t } = useI18n();
const serverError = useServerError();

interface Col { label: string; value: (r: MasterRow) => string; num?: boolean }
const acc = (r: MasterRow) => {
  const a = r.account as { code?: string; name?: string } | null;
  return a ? `${a.code} · ${a.name}` : "";
};
const ACCOUNT = "*, account:m_accounts(code, name)";
const base = props.kind.split(":")[0];
const CONFIG: Record<string, { table: MasterTable; parent: string; columns: string; order: string; cols: Col[] }> = {
  journal: {
    table: "t_journal_lines", parent: "journal_id", columns: ACCOUNT, order: "line_no",
    cols: [
      { label: t("common.account"), value: acc },
      { label: t("common.description"), value: (r) => String(r.memo ?? "") },
      { label: t("common.debit"), value: (r) => formatAmount(r.debit), num: true },
      { label: t("common.credit"), value: (r) => formatAmount(r.credit), num: true },
    ],
  },
  invoice: {
    table: "t_invoice_lines", parent: "invoice_id", columns: ACCOUNT, order: "line_no",
    cols: [
      { label: t("common.description"), value: (r) => String(r.description ?? "") },
      { label: t("common.account"), value: acc },
      { label: t("approvals.qty"), value: (r) => formatQty(r.qty), num: true },
      { label: t("approvals.unitPrice"), value: (r) => formatAmount(r.unit_price), num: true },
      { label: t("approvals.tax"), value: (r) => formatAmount(r.tax_amount), num: true },
      { label: t("approvals.subtotal"), value: (r) => formatAmount(r.line_subtotal), num: true },
    ],
  },
  payment: {
    table: "t_payment_allocations", parent: "payment_id", columns: "*, invoice:t_invoices(doc_no, invoice_date, total)", order: "id",
    cols: [
      { label: t("approvals.document"), value: (r) => String((r.invoice as { doc_no?: string } | null)?.doc_no ?? "") },
      { label: t("common.date"), value: (r) => formatDate((r.invoice as { invoice_date?: string } | null)?.invoice_date) },
      { label: t("approvals.docTotal"), value: (r) => formatAmount((r.invoice as { total?: number } | null)?.total), num: true },
      { label: t("approvals.allocated"), value: (r) => formatAmount(r.amount), num: true },
    ],
  },
  cash: {
    table: "t_cash_txn_lines", parent: "txn_id", columns: ACCOUNT, order: "id",
    cols: [
      { label: t("common.account"), value: acc },
      { label: t("common.description"), value: (r) => String(r.description ?? "") },
      { label: t("approvals.tax"), value: (r) => formatAmount(r.tax_amount), num: true },
      { label: t("common.amount"), value: (r) => formatAmount(r.amount), num: true },
    ],
  },
  expense: {
    table: "t_expense_claim_lines", parent: "claim_id", columns: ACCOUNT, order: "expense_date",
    cols: [
      { label: t("common.date"), value: (r) => formatDate(r.expense_date as string) },
      { label: t("common.account"), value: acc },
      { label: t("common.description"), value: (r) => String(r.description ?? "") },
      { label: t("common.amount"), value: (r) => formatAmount(r.amount), num: true },
    ],
  },
};
const cfg = CONFIG[base] ?? CONFIG.journal;
const lines = useMasterRows(cfg.table, { filter: { [cfg.parent]: props.id }, columns: cfg.columns, order: cfg.order });
const rows = computed(() => lines.data.value ?? []);
const view = async (path: string) => {
  try {
    await openReceipt(path);
  } catch (err) {
    toast.error(serverError(err));
  }
};
</script>

<template>
  <LoadingState v-if="lines.isPending.value" :columns="cfg.cols.length" :rows="3" />
  <EmptyState v-else-if="lines.isError.value" compact :title="t('common.loadFailed')">
    <Button variant="outline" size="sm" @click="lines.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
  </EmptyState>
  <EmptyState v-else-if="!rows.length" compact :title="base === 'payment' ? t('approvals.unallocated') : t('common.empty')" />
  <div v-else class="overflow-x-auto rounded-lg border">
    <table v-stack class="w-full text-sm">
      <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
        <tr>
          <th v-for="c in cfg.cols" :key="c.label" :class="['px-3 py-2 font-medium', c.num && 'text-right']">{{ c.label }}</th>
          <th v-if="base === 'expense'" class="w-px px-3 py-2 font-medium">{{ t("expenses.receipt") }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
          <td v-for="c in cfg.cols" :key="c.label" :class="c.num && 'text-right tabular-nums whitespace-nowrap'">{{ c.value(r) }}</td>
          <td v-if="base === 'expense'">
            <Button v-if="r.receipt_path" variant="ghost" size="icon" class="size-8" :tooltip="t('expenses.receipt')" @click="view(String(r.receipt_path))"><FileText /></Button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
