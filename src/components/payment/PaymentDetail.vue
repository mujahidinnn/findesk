<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { BookOpen, Check, Pencil, Send, Trash2, Undo2 } from "@lucide/vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import ReasonDialog from "@/components/common/ReasonDialog.vue";
import AmountInput from "@/components/invoice/AmountInput.vue";
import { docLabel, featureOf, nameOf, openOf, PAYMENT_TARGETS, type Direction } from "@/components/invoice/docTypes";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useDeleteMasterRow, useMasterRows } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { useAuthStore } from "@/stores/auth";
import { formatDate, formatMoney, formatRate, round2 } from "@/lib/format";

const id = defineModel<number | null>("id", { required: true });
const emit = defineEmits<{ edit: [id: number] }>();
const { t } = useI18n();
const { can } = usePermissions();
const auth = useAuthStore();
const serverError = useServerError();

const query = useMasterRows("t_payments", {
  filter: () => ({ id: id.value }),
  columns: "*, partner:m_partners(name, code), bank:m_bank_accounts(name, currency), wht:m_taxes(name)",
  enabled: () => !!id.value,
});
const pay = computed(() => query.data.value?.[0] ?? null);
const allocations = useMasterRows("t_payment_allocations", {
  filter: () => ({ payment_id: id.value }),
  columns: "id, amount, applied_date, invoice:t_invoices(id, doc_no, doc_type, invoice_date)",
  enabled: () => !!id.value,
});
const direction = computed(() => (pay.value?.direction ?? "in") as Direction);
const feature = computed(() => featureOf(direction.value));
const money = (v: unknown) => formatMoney(v, String(pay.value?.currency ?? "IDR"));
const unallocated = computed(() => (pay.value ? round2(Number(pay.value.amount) + Number(pay.value.wht_amount) - Number(pay.value.allocated_amount)) : 0));
const invoiceLink = (inv: { id: number; doc_type: string }) => `${inv.doc_type.startsWith("sales") ? "/sales/invoices" : "/purchases/bills"}?id=${inv.id}`;

const canAllocate = computed(() => pay.value?.status === "posted" && unallocated.value > 0 && can(feature.value, "update"));
const openDocs = useMasterRows("t_invoices", {
  filter: () => ({ partner_id: pay.value?.partner_id, currency: pay.value?.currency, status: "posted" }),
  columns: "id, doc_no, doc_type, due_date, total, paid_amount",
  order: "due_date",
  enabled: () => canAllocate.value,
});
const targets = computed(() => (openDocs.data.value ?? []).filter((r) => PAYMENT_TARGETS[direction.value].includes(r.doc_type as never)));
const extra = ref<Record<number, number | null>>({});
watch(id, () => (extra.value = {}));

const submit = useRpcMutation("submit_payment", ["t_payments", "t_invoices"]);
const voidPay = useRpcMutation("void_payment", ["t_payments", "t_invoices", "t_payment_allocations"]);
const allocate = useRpcMutation("allocate_payment", ["t_payments", "t_invoices", "t_payment_allocations"]);
const remove = useDeleteMasterRow("t_payments");

const voiding = ref(false);
const deleting = ref(false);
async function run(action: () => Promise<unknown>, ok = t("common.saved")) {
  try {
    await action();
    toast.success(ok);
    return true;
  } catch (err) {
    toast.error(serverError(err));
    return false;
  }
}
const doSubmit = () =>
  run(async () => {
    const r = await submit.mutateAsync({ p_id: id.value! });
    if (r === "submitted") toast.info(t("invoices.submittedForApproval"));
  });
async function doVoid(reason: string) {
  if (await run(() => voidPay.mutateAsync({ p_id: id.value!, p_reason: reason }))) voiding.value = false;
}
async function doDelete() {
  if (await run(() => remove.mutateAsync(id.value!))) {
    deleting.value = false;
    id.value = null;
  }
}
async function doAllocate(invoiceId: number) {
  const amount = extra.value[invoiceId];
  if (!amount || amount <= 0) return;
  if (await run(() => allocate.mutateAsync({ p_payment_id: id.value!, p_invoice_id: invoiceId, p_amount: amount }))) extra.value[invoiceId] = null;
}

const open = computed({ get: () => !!id.value, set: (v) => { if (!v) id.value = null; } });
const fields = computed(() => {
  const p = pay.value;
  if (!p) return [];
  return [
    [t(direction.value === "in" ? "invoices.customer" : "invoices.vendor"), nameOf(p.partner)],
    [t("common.date"), formatDate(String(p.payment_date))],
    [t("payments.bankAccount"), nameOf(p.bank)],
    [t("common.amount"), money(p.amount)],
    p.currency !== "IDR" ? [t("common.rate"), formatRate(p.fx_rate)] : null,
    Number(p.wht_amount) > 0 ? [t("payments.whtTax"), `${nameOf(p.wht)} · ${money(p.wht_amount)}${p.wht_slip_no ? ` · ${p.wht_slip_no}` : ""}`] : null,
    [t("payments.allocated"), money(p.allocated_amount)],
    [t("common.reference"), p.reference],
    [t("common.note"), p.note],
    [t("invoices.voidReason"), p.void_reason],
    [t("invoices.rejectReason"), p.reject_reason],
  ].filter((f): f is [string, string] => !!f && !!f[1]);
});
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-3xl">
      <DialogHeader>
        <DialogTitle class="font-mono">{{ pay ? docLabel(pay) : "" }}</DialogTitle>
        <DialogDescription class="flex items-center gap-2">
          {{ t(`payments.kinds.${direction}`) }}
          <DocStatus v-if="pay" :status="String(pay.status)" />
        </DialogDescription>
      </DialogHeader>
      <LoadingState v-if="query.isPending.value" variant="detail" />
      <EmptyState v-else-if="!pay" :title="t('common.loadFailed')" />
      <div v-else class="max-h-[72vh] space-y-4 overflow-y-auto">
        <div class="flex flex-wrap gap-2">
          <template v-if="pay.status === 'draft'">
            <Button v-if="can(feature, 'update') || can(feature, 'create')" size="sm" variant="outline" @click="emit('edit', pay.id)"><Pencil /> {{ t("common.edit") }}</Button>
            <Button v-if="can(feature, 'update') || can(feature, 'create')" size="sm" class="active:scale-95" :loading="submit.isPending.value" @click="doSubmit"><Send /> {{ t("invoices.post") }}</Button>
            <Button v-if="can(feature, 'delete') || pay.created_by === auth.user?.id" size="sm" variant="ghost-destructive" @click="deleting = true"><Trash2 /> {{ t("common.delete") }}</Button>
          </template>
          <Button v-if="pay.status === 'posted' && can(feature, 'delete')" size="sm" variant="ghost-destructive" @click="voiding = true"><Undo2 /> {{ t("common.void") }}</Button>
          <Button v-if="pay.journal_id" as-child size="sm" variant="outline">
            <RouterLink :to="`/journals?id=${pay.journal_id}`"><BookOpen /> {{ t("common.openJournal") }}</RouterLink>
          </Button>
        </div>

        <dl class="bg-secondary/50 grid gap-x-6 gap-y-3 rounded-lg p-4 sm:grid-cols-3">
          <div v-for="[label, value] in fields" :key="label" class="min-w-0">
            <dt class="text-muted-foreground text-xs">{{ label }}</dt>
            <dd class="truncate text-sm font-medium">{{ value }}</dd>
          </div>
        </dl>

        <section class="space-y-2">
          <h3 class="text-sm font-semibold">{{ t("payments.allocations") }}</h3>
          <EmptyState v-if="!allocations.data.value?.length" :title="t('payments.noAllocations')" compact />
          <ul v-else class="divide-y rounded-lg border text-sm">
            <li v-for="a in allocations.data.value" :key="a.id" class="flex items-center gap-3 px-3 py-2">
              <span class="min-w-0 flex-1">
                <RouterLink :to="invoiceLink(a.invoice as never)" class="text-primary-text font-mono text-xs hover:underline" @click="open = false">
                  {{ (a.invoice as { doc_no: string } | null)?.doc_no }}
                </RouterLink>
                <span class="text-muted-foreground block text-xs">{{ formatDate(a.applied_date as string | null) }}</span>
              </span>
              <span class="font-medium tabular-nums">{{ money(a.amount) }}</span>
            </li>
          </ul>
          <p v-if="pay.status === 'posted' && unallocated > 0" class="text-muted-foreground text-xs">
            {{ t("payments.unallocated") }}: <span class="text-foreground font-medium tabular-nums">{{ money(unallocated) }}</span> · {{ t("payments.advanceHint") }}
          </p>
        </section>

        <section v-if="canAllocate" class="space-y-2">
          <h3 class="text-sm font-semibold">{{ t("payments.allocateRemaining") }}</h3>
          <EmptyState v-if="!targets.length" :title="t('payments.noOpenDocs')" compact />
          <div v-for="d in targets" :key="d.id" class="flex flex-wrap items-center gap-2 rounded-lg border px-3 py-2 text-sm">
            <span class="min-w-0 flex-1">
              <span class="font-mono text-xs">{{ docLabel(d) }}</span>
              <span class="text-muted-foreground block text-xs">{{ t("invoices.open") }} {{ money(openOf(d)) }}</span>
            </span>
            <AmountInput :model-value="extra[d.id] ?? null" :currency="String(pay.currency)" :max="Math.min(openOf(d), unallocated)" class="w-40" :aria-label="docLabel(d)" @update:model-value="extra[d.id] = $event" />
            <Button size="icon" variant="soft" class="size-8" :tooltip="t('payments.allocate')" :disabled="!extra[d.id] || allocate.isPending.value" @click="doAllocate(d.id)"><Check /></Button>
          </div>
        </section>
      </div>
    </DialogContent>
  </Dialog>

  <ReasonDialog v-model:open="voiding" :title="t('payments.voidTitle')" :description="t('payments.voidBody')" :confirm-label="t('common.void')" :busy="voidPay.isPending.value" destructive @confirm="doVoid" />
  <ConfirmDialog v-model:open="deleting" :title="t('common.deleteTitle')" :description="t('common.deleteBody')" :confirm-label="t('common.delete')" :busy="remove.isPending.value" destructive @confirm="doDelete" />
</template>
