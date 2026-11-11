<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Banknote, BookOpen, Building2, FileCheck2, HandCoins, Paperclip, Pencil, Printer, Send, Trash2, Undo2 } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import ReasonDialog from "@/components/common/ReasonDialog.vue";
import AmountInput from "@/components/invoice/AmountInput.vue";
import { directionFor, docLabel, featureOf, isNote, nameOf, noteTarget, openOf, sideOf, type DocType } from "@/components/invoice/docTypes";
import PaymentEditor, { type PaymentPreset } from "@/components/payment/PaymentEditor.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, formatQty, formatRate, isoDate, round2 } from "@/lib/format";
import { accountName, costCenterName } from "@/lib/accountName";
import { FIELD_CLASS } from "@/lib/utils";

const ccLabel = (v: unknown) => { const c = v as { code?: string; name?: string } | null; return c?.name ? costCenterName(String(c.code), c.name) : ""; };
import { useAuthStore } from "@/stores/auth";

const id = defineModel<number | null>("id", { required: true });
const emit = defineEmits<{ edit: [id: number, docType: DocType] }>();
const { t } = useI18n();
const { can } = usePermissions();
const auth = useAuthStore();
const serverError = useServerError();

const query = useMasterRows("t_invoices", {
  filter: () => ({ id: id.value }),
  columns: "*, partner:m_partners(name, code, npwp), original:t_invoices!original_invoice_id(id, doc_no), term:m_payment_terms(name), cost_center:m_cost_centers(code, name), project:m_projects(name)",
  enabled: () => !!id.value,
});
const inv = computed(() => query.data.value?.[0] ?? null);
const enabled = () => !!id.value;
const lines = useMasterRows("t_invoice_lines", {
  filter: () => ({ invoice_id: id.value }),
  columns: "*, item:m_items(code, name, unit), account:m_accounts(code, name, subtype), tax:m_taxes!tax_id(name), wht:m_taxes!wht_tax_id(name)",
  order: "line_no",
  enabled,
});
const allocations = useMasterRows("t_payment_allocations", {
  filter: () => ({ invoice_id: id.value }),
  columns: "id, amount, applied_date, payment:t_payments(id, doc_no, direction, payment_date, status)",
  enabled,
});
const asNote = useMasterRows("t_note_applications", {
  filter: () => ({ note_id: id.value }),
  columns: "id, amount, applied_date, other:t_invoices!invoice_id(id, doc_no, doc_type)",
  enabled,
});
const asTarget = useMasterRows("t_note_applications", {
  filter: () => ({ invoice_id: id.value }),
  columns: "id, amount, applied_date, other:t_invoices!note_id(id, doc_no, doc_type)",
  enabled,
});
const applications = computed(() => [...(asNote.data.value ?? []), ...(asTarget.data.value ?? [])]);

const docType = computed(() => String(inv.value?.doc_type ?? "sales_invoice"));
const side = computed(() => sideOf(docType.value));
const feature = computed(() => featureOf(docType.value));
const currency = computed(() => String(inv.value?.currency ?? "IDR"));
const money = (v: unknown) => formatMoney(v, currency.value);
const open = computed(() => (inv.value ? openOf(inv.value) : 0));
const docLink = (d: { id: number; doc_type: string }) => `${d.doc_type.startsWith("sales") ? "/sales/invoices" : "/purchases/bills"}?id=${d.id}`;
const payLink = (p: { id: number; direction: string }) => `${p.direction === "in" ? "/sales/receipts" : "/purchases/payments"}?id=${p.id}`;

const submit = useRpcMutation("submit_invoice", ["t_invoices"]);
const voidInv = useRpcMutation("void_invoice", ["t_invoices"]);
const setFaktur = useRpcMutation("set_tax_invoice_no", ["t_invoices"]);
const applyNote = useRpcMutation("apply_credit_note", ["t_invoices", "t_note_applications", "aging"]);
const unapplyNote = useRpcMutation("unapply_credit_note", ["t_invoices", "t_note_applications", "aging"]);
const remove = useDeleteMasterRow("t_invoices");

async function run(action: () => Promise<unknown>) {
  try {
    await action();
    toast.success(t("common.saved"));
    return true;
  } catch (err) {
    toast.error(serverError(err));
    return false;
  }
}
async function doSubmit() {
  try {
    const r = await submit.mutateAsync({ p_id: id.value! });
    toast.success(t(r === "submitted" ? "invoices.submittedForApproval" : "invoices.postedOk"));
  } catch (err) {
    toast.error(serverError(err));
  }
}

const voiding = ref(false);
async function doVoid(reason: string) {
  if (await run(() => voidInv.mutateAsync({ p_id: id.value!, p_reason: reason }))) voiding.value = false;
}
const deleting = ref(false);
async function doDelete() {
  if (await run(() => remove.mutateAsync(id.value!))) {
    deleting.value = false;
    id.value = null;
  }
}

const faktur = ref({ open: false, no: "", date: isoDate() });
function openFaktur() {
  faktur.value = { open: true, no: String(inv.value?.tax_invoice_no ?? ""), date: String(inv.value?.tax_invoice_date ?? inv.value?.invoice_date ?? isoDate()) };
}
async function saveFaktur() {
  if (await run(() => setFaktur.mutateAsync({ p_id: id.value!, p_no: faktur.value.no, p_date: faktur.value.date }))) faktur.value.open = false;
}

const applying = ref({ open: false, invoiceId: null as number | null, amount: null as number | null, date: isoDate() });
const unapplying = ref<number | null>(null);
const unapplyOpen = computed({ get: () => unapplying.value != null, set: (v) => { if (!v) unapplying.value = null; } });
async function doUnapply() {
  if (await run(() => unapplyNote.mutateAsync({ p_application_id: unapplying.value! }))) unapplying.value = null;
}
const targets = useMasterRows("t_invoices", {
  filter: () => ({ partner_id: inv.value?.partner_id, currency: currency.value, doc_type: noteTarget(docType.value), status: "posted" }),
  columns: "id, doc_no, due_date, total, paid_amount",
  order: "due_date",
  enabled: () => applying.value.open,
});
const targetOptions = computed(() => (targets.data.value ?? []).map((r) => ({ value: r.id, label: `${docLabel(r)} · ${t("invoices.open")} ${money(openOf(r))}` })));
watch(
  () => applying.value.invoiceId,
  (tid) => {
    const target = targets.data.value?.find((r) => r.id === tid);
    if (target) applying.value.amount = round2(Math.min(open.value, openOf(target)));
  },
);
async function doApply() {
  const a = applying.value;
  if (!a.invoiceId || !a.amount) return;
  if (await run(() => applyNote.mutateAsync({ p_note_id: id.value!, p_invoice_id: a.invoiceId!, p_amount: a.amount!, p_date: a.date }))) applying.value.open = false;
}

const paying = ref(false);
const preset = computed<PaymentPreset | null>(() => (inv.value ? { partnerId: Number(inv.value.partner_id), invoiceId: inv.value.id, currency: currency.value } : null));
const payDirection = computed(() => directionFor(docType.value));

async function viewAttachment() {
  const path = inv.value?.attachment_path as string | null;
  if (!path) return;
  const { data, error } = await supabase.storage.from("attachments").createSignedUrl(path, 300);
  if (error) return void toast.error(serverError(error));
  window.open(data.signedUrl, "_blank", "noopener");
}

const can_ = (action: "create" | "update" | "delete") => can(feature.value, action);
const canEditDraft = computed(() => inv.value?.status === "draft" && (can_("update") || (can_("create") && inv.value.created_by === auth.user?.id)));
const live = computed(() => inv.value?.status === "posted" || inv.value?.status === "paid");

const dialogOpen = computed({ get: () => !!id.value, set: (v) => { if (!v) id.value = null; } });
const fields = computed(() => {
  const r = inv.value;
  if (!r) return [];
  return [
    [t(side.value === "sales" ? "invoices.customer" : "invoices.vendor"), nameOf(r.partner), `/partners?id=${r.partner_id}`],
    [t("common.date"), formatDate(String(r.invoice_date))],
    [t("invoices.dueDate"), formatDate(r.due_date as string | null)],
    [t("invoices.term"), nameOf(r.term)],
    r.currency !== "IDR" ? [t("common.rate"), `${r.currency} · ${formatRate(r.fx_rate)}`] : null,
    [t(side.value === "sales" ? "common.reference" : "invoices.vendorRef"), r.reference],
    [t("invoices.originalInvoice"), (r.original as MasterRow | null)?.doc_no, r.original_invoice_id ? docLink({ id: Number(r.original_invoice_id), doc_type: noteTarget(docType.value) }) : null],
    [t("invoices.taxInvoiceNo"), r.tax_invoice_no ? `${r.tax_invoice_no}${r.tax_invoice_date ? ` · ${formatDate(String(r.tax_invoice_date))}` : ""}` : null],
    [t("common.costCenter"), ccLabel(r.cost_center)],
    [t("common.project"), nameOf(r.project)],
    [t("common.note"), r.note],
    [t("invoices.voidReason"), r.void_reason],
    [t("invoices.rejectReason"), r.reject_reason],
  ].filter((f): f is [string, string, string?] => !!f && !!f[1]);
});
type Line = MasterRow & { item: { code: string; name: string; unit: string } | null; account: { code: string; name: string; subtype: string } | null };
</script>

<template>
  <Dialog v-model:open="dialogOpen">
    <DialogContent class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle class="font-mono">{{ inv ? docLabel(inv) : "" }}</DialogTitle>
        <DialogDescription class="flex items-center gap-2">
          {{ t(`invoices.kinds.${docType}`) }}
          <DocStatus v-if="inv" :status="String(inv.status)" :paid="inv.paid_amount" :total="inv.total" :due="inv.due_date as string" />
        </DialogDescription>
      </DialogHeader>
      <LoadingState v-if="query.isPending.value" variant="detail" />
      <EmptyState v-else-if="!inv" :title="t('common.loadFailed')" />
      <div v-else class="max-h-[74vh] space-y-4 overflow-y-auto">
        <div class="flex flex-wrap gap-2">
          <template v-if="inv.status === 'draft'">
            <Button v-if="canEditDraft" size="sm" variant="outline" @click="emit('edit', inv.id, docType as DocType)"><Pencil /> {{ t("common.edit") }}</Button>
            <Button v-if="canEditDraft" size="sm" class="active:scale-95" :loading="submit.isPending.value" @click="doSubmit"><Send /> {{ t("invoices.post") }}</Button>
            <Button v-if="can_('delete') || inv.created_by === auth.user?.id" size="sm" variant="ghost-destructive" @click="deleting = true"><Trash2 /> {{ t("common.delete") }}</Button>
          </template>
          <Button v-if="inv.status === 'posted' && open > 0 && can(featureOf(payDirection), 'create')" size="sm" class="active:scale-95" @click="paying = true">
            <Banknote /> {{ t(isNote(docType) ? "invoices.recordRefund" : "invoices.recordPayment") }}
          </Button>
          <Button v-if="isNote(docType) && inv.status === 'posted' && open > 0 && can_('update')" size="sm" variant="outline" @click="applying = { open: true, invoiceId: null, amount: null, date: isoDate() }">
            <HandCoins /> {{ t("invoices.applyNote") }}
          </Button>
          <Button v-if="live && (can_('update') || can('tax', 'update'))" size="sm" variant="outline" @click="openFaktur"><FileCheck2 /> {{ t("invoices.setTaxInvoice") }}</Button>
          <Button v-if="inv.status !== 'draft'" as-child size="sm" variant="outline">
            <RouterLink :to="`/print/invoice/${inv.id}`" target="_blank"><Printer /> {{ t("common.print") }}</RouterLink>
          </Button>
          <Button v-if="inv.attachment_path" size="sm" variant="outline" @click="viewAttachment"><Paperclip /> {{ t("invoices.viewAttachment") }}</Button>
          <Button v-if="inv.journal_id" as-child size="sm" variant="outline">
            <RouterLink :to="`/journals?id=${inv.journal_id}`"><BookOpen /> {{ t("common.openJournal") }}</RouterLink>
          </Button>
          <Button v-if="inv.status === 'posted' && Number(inv.paid_amount) === 0 && can_('delete')" size="sm" variant="ghost-destructive" @click="voiding = true">
            <Undo2 /> {{ t("common.void") }}
          </Button>
        </div>

        <dl class="bg-secondary/50 grid gap-x-6 gap-y-3 rounded-lg p-4 sm:grid-cols-3">
          <div v-for="[label, value, to] in fields" :key="label" class="min-w-0">
            <dt class="text-muted-foreground text-xs">{{ label }}</dt>
            <dd class="truncate text-sm font-medium">
              <RouterLink v-if="to" :to="to" class="text-primary-text hover:underline">{{ value }}</RouterLink>
              <template v-else>{{ value }}</template>
            </dd>
          </div>
        </dl>

        <LoadingState v-if="lines.isPending.value" :columns="6" :rows="3" />
        <div v-else class="overflow-x-auto rounded-lg border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr class="[&>th]:px-3 [&>th]:py-2 [&>th]:font-medium">
                <th>{{ t("common.description") }}</th>
                <th>{{ t("common.account") }}</th>
                <th class="text-right">{{ t("invoices.qty") }}</th>
                <th class="text-right">{{ t("invoices.unitPrice") }}</th>
                <th class="text-right">{{ t("invoices.discount") }}</th>
                <th class="text-right">{{ t("invoices.lineSubtotal") }}</th>
                <th class="text-right">{{ t("invoices.vat") }}</th>
                <th v-if="side === 'purchase'" class="text-right">{{ t("invoices.wht") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="l in lines.data.value as Line[]" :key="l.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                <td>
                  {{ l.description || l.item?.name }}
                  <span v-if="l.item" class="text-muted-foreground ml-1 font-mono text-xs">{{ l.item.code }}</span>
                </td>
                <td class="text-xs">
                  {{ l.account ? `${l.account.code} · ${accountName(l.account.code, l.account.name)}` : t("invoices.itemAccount") }}
                  <RouterLink
                    v-if="docType === 'purchase_bill' && live && l.account?.subtype === 'fixed_asset' && can('asset', 'create')"
                    :to="`/assets?bill=${inv.id}&line=${l.id}`" class="text-primary-text mt-0.5 flex items-center gap-1 hover:underline"
                  >
                    <Building2 class="size-3" /> {{ t("invoices.createAsset") }}
                  </RouterLink>
                </td>
                <td class="text-right tabular-nums">{{ formatQty(l.qty) }} <span class="text-muted-foreground text-xs">{{ l.item?.unit }}</span></td>
                <td class="text-right tabular-nums">{{ money(l.unit_price) }}</td>
                <td class="text-right tabular-nums">{{ Number(l.discount) ? money(l.discount) : "-" }}</td>
                <td class="text-right font-medium tabular-nums">{{ money(l.line_subtotal) }}</td>
                <td class="text-right tabular-nums">
                  {{ Number(l.tax_amount) ? money(l.tax_amount) : "-" }}
                  <span v-if="l.tax" class="text-muted-foreground block text-[11px]">{{ nameOf(l.tax) }}</span>
                </td>
                <td v-if="side === 'purchase'" class="text-right tabular-nums">
                  {{ Number(l.wht_amount) ? money(l.wht_amount) : "-" }}
                  <span v-if="l.wht" class="text-muted-foreground block text-[11px]">{{ nameOf(l.wht) }}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-3">
            <section class="space-y-2">
              <h3 class="text-sm font-semibold">{{ t("invoices.payments") }}</h3>
              <EmptyState v-if="!allocations.data.value?.length" :title="t('invoices.noPayments')" compact />
              <ul v-else class="divide-y rounded-lg border text-sm">
                <li v-for="a in allocations.data.value" :key="a.id" class="flex items-center gap-3 px-3 py-2">
                  <span class="min-w-0 flex-1">
                    <RouterLink :to="payLink(a.payment as never)" class="text-primary-text font-mono text-xs hover:underline">{{ docLabel(a.payment as never) }}</RouterLink>
                    <span class="text-muted-foreground block text-xs">{{ formatDate((a.applied_date ?? (a.payment as MasterRow | null)?.payment_date) as string | null) }}</span>
                  </span>
                  <span class="font-medium tabular-nums">{{ money(a.amount) }}</span>
                </li>
              </ul>
            </section>
            <section v-if="applications.length" class="space-y-2">
              <h3 class="text-sm font-semibold">{{ t("invoices.noteApplications") }}</h3>
              <ul class="divide-y rounded-lg border text-sm">
                <li v-for="a in applications" :key="a.id" class="flex items-center gap-3 px-3 py-2">
                  <span class="min-w-0 flex-1">
                    <RouterLink :to="docLink(a.other as never)" class="text-primary-text font-mono text-xs hover:underline">{{ (a.other as MasterRow | null)?.doc_no }}</RouterLink>
                    <span class="text-muted-foreground block text-xs">{{ formatDate(a.applied_date as string) }}</span>
                  </span>
                  <span class="font-medium tabular-nums">{{ money(a.amount) }}</span>
                  <Button v-if="live && can_('update')" size="icon" variant="ghost" class="size-7" :tooltip="t('invoices.unapply')" @click="unapplying = a.id as number"><Undo2 /></Button>
                </li>
              </ul>
            </section>
          </div>
          <dl class="space-y-1 self-start text-sm tabular-nums sm:ml-auto sm:min-w-64">
            <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.subtotal") }}</dt><dd>{{ money(inv.subtotal) }}</dd></div>
            <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.vat") }}</dt><dd>{{ money(inv.tax_total) }}</dd></div>
            <div v-if="Number(inv.wht_total)" class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.wht") }}</dt><dd>({{ money(inv.wht_total) }})</dd></div>
            <div class="flex justify-between gap-6 border-t border-dashed pt-1 font-semibold"><dt>{{ t("common.total") }}</dt><dd>{{ money(inv.total) }}</dd></div>
            <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.settled") }}</dt><dd>{{ money(inv.paid_amount) }}</dd></div>
            <div class="flex justify-between gap-6 font-semibold"><dt>{{ t("invoices.open") }}</dt><dd>{{ money(open) }}</dd></div>
          </dl>
        </div>
      </div>
    </DialogContent>
  </Dialog>

  <ReasonDialog v-model:open="voiding" :title="t('invoices.voidTitle')" :description="t('invoices.voidBody')" :confirm-label="t('common.void')" :busy="voidInv.isPending.value" destructive @confirm="doVoid" />
  <ConfirmDialog v-model:open="deleting" :title="t('common.deleteTitle')" :description="t('common.deleteBody')" :confirm-label="t('common.delete')" :busy="remove.isPending.value" destructive @confirm="doDelete" />

  <ConfirmDialog v-model:open="unapplyOpen" :title="t('invoices.unapplyTitle')" :description="t('invoices.unapplyBody')" :confirm-label="t('invoices.unapply')" :busy="unapplyNote.isPending.value" destructive @confirm="doUnapply" />

  <Dialog v-model:open="faktur.open">
    <DialogContent class="sm:max-w-sm">
      <DialogHeader>
        <DialogTitle>{{ t("invoices.setTaxInvoice") }}</DialogTitle>
        <DialogDescription>{{ t("invoices.taxInvoiceHint") }}</DialogDescription>
      </DialogHeader>
      <form id="faktur-form" class="space-y-3" @submit.prevent="saveFaktur">
        <div class="space-y-1.5">
          <Label for="faktur-no">{{ t("invoices.taxInvoiceNo") }}</Label>
          <input id="faktur-no" v-model="faktur.no" :class="[FIELD_CLASS, 'font-mono']" placeholder="010.000-26.00000001" />
        </div>
        <div class="space-y-1.5">
          <Label for="faktur-date">{{ t("invoices.taxInvoiceDate") }}</Label>
          <input id="faktur-date" v-model="faktur.date" type="date" required :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="faktur.open = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="faktur-form" :loading="setFaktur.isPending.value" :disabled="setFaktur.isPending.value">{{ t("common.save") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <Dialog v-model:open="applying.open">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>{{ t("invoices.applyNote") }}</DialogTitle>
        <DialogDescription>{{ t("invoices.noteOpen", { amount: money(open) }) }}</DialogDescription>
      </DialogHeader>
      <form id="apply-form" class="space-y-3" @submit.prevent="doApply">
        <div class="space-y-1.5">
          <Label for="apply-target">{{ t(`invoices.kinds.${noteTarget(docType)}`) }}</Label>
          <AppSelect id="apply-target" v-model="applying.invoiceId" :options="targetOptions" :placeholder="targets.isPending.value ? t('common.loading') : t('common.pick')" required />
          <p v-if="!targets.isPending.value && !targetOptions.length" class="text-muted-foreground text-xs">{{ t("payments.noOpenDocs") }}</p>
        </div>
        <div class="space-y-1.5">
          <Label for="apply-amount">{{ t("common.amount") }}</Label>
          <AmountInput id="apply-amount" v-model="applying.amount" :currency="currency" :max="open" required />
        </div>
        <div class="space-y-1.5">
          <Label for="apply-date">{{ t("common.date") }}</Label>
          <input id="apply-date" v-model="applying.date" type="date" required :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="applying.open = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="apply-form" :loading="applyNote.isPending.value" :disabled="applyNote.isPending.value || !applying.invoiceId || !applying.amount">
          <HandCoins /> {{ t("invoices.apply") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <PaymentEditor v-model:open="paying" :direction="payDirection" :preset="preset" />
</template>
