<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ArrowDownLeft, ArrowUpRight, BookOpen, Info, Pencil, Plus, Save, Send, Trash2, Undo2, X } from "@lucide/vue";
import AmountInput from "@/components/cash/AmountInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import ReasonDialog from "@/components/common/ReasonDialog.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useAccountOptions, useBankOptions, usePartnerOptions, useSimpleOptions, useTaxOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, formatRate, isoDate, round2 } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { useAuthStore } from "@/stores/auth";

const props = defineProps<{ base: string }>();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const txns = useMasterRows("t_cash_txns", { descending: true });
const banks = useBankOptions();
const partners = usePartnerOptions(undefined);
const accounts = useAccountOptions({ exclude: ["cash", "bank"] });
const accountOptions = computed(() => {
  const control = new Set((accounts.rows.data.value ?? []).filter((a) => a.is_control).map((a) => a.id));
  return accounts.options.value.filter((o) => !control.has(o.value));
});
const taxes = useTaxOptions("vat");
const costCenters = useSimpleOptions("m_cost_centers");
const projects = useSimpleOptions("m_projects");

const bank = (id: unknown) => banks.rows.data.value?.find((b) => b.id === id);
const partner = (id: unknown) => partners.rows.data.value?.find((p) => p.id === id);
const account = (id: unknown) => accounts.rows.data.value?.find((a) => a.id === id);
const docNo = (r: MasterRow) => (r.doc_no as string | null) ?? `${t("cash.draftNo")}${r.id}`;
const canEdit = (r: MasterRow) =>
  r.status === "draft" && (can("cash-bank", "update") || (r.created_by === auth.user?.id && can("cash-bank", "create")));

const run = async (action: () => Promise<unknown>, done = t("common.saved")) => {
  try {
    await action();
    toast.success(done);
    return true;
  } catch (err) {
    toast.error(serverError(err));
    return false;
  }
};

const detailId = ref<number | null>(Number(route.query.id) || null);
watch(() => route.query.id, (v) => (detailId.value = Number(v) || null));
const detail = computed(() => txns.data.value?.find((r) => r.id === detailId.value) ?? null);
const detailLines = useMasterRows("t_cash_txn_lines", { filter: () => ({ txn_id: detailId.value }), enabled: () => !!detailId.value });
function closeDetail() {
  detailId.value = null;
  if (route.query.id) void router.replace({ query: { ...route.query, id: undefined } });
}

interface Line { id?: number; account_id: number | null; description: string; amount: number | null; tax_id: number | null; cost_center_id: number | null; project_id: number | null }
interface Header { id?: number; direction: "in" | "out"; bank_account_id: number | null; txn_date: string; fx_rate: number | null; partner_id: number | null; payee: string; reference: string; description: string; tax_invoice_no: string; tax_invoice_date: string }
const editor = ref<Header | null>(null);
const lines = ref<Line[]>([]);
const removed = ref<number[]>([]);
const blankLine = (): Line => ({ account_id: null, description: "", amount: null, tax_id: null, cost_center_id: null, project_id: null });

function startNew(direction: "in" | "out") {
  editor.value = { direction, bank_account_id: null, txn_date: isoDate(), fx_rate: null, partner_id: null, payee: "", reference: "", description: "", tax_invoice_no: "", tax_invoice_date: "" };
  lines.value = [blankLine()];
  removed.value = [];
}
function startEdit(r: MasterRow) {
  editor.value = {
    id: r.id, direction: r.direction as "in" | "out", bank_account_id: r.bank_account_id as number, txn_date: String(r.txn_date),
    fx_rate: Number(r.fx_rate), partner_id: (r.partner_id as number | null) ?? null, payee: String(r.payee ?? ""),
    reference: String(r.reference ?? ""), description: String(r.description ?? ""),
    tax_invoice_no: String(r.tax_invoice_no ?? ""), tax_invoice_date: String(r.tax_invoice_date ?? ""),
  };
  lines.value = (detailLines.data.value ?? []).map((l) => ({
    id: l.id, account_id: l.account_id as number, description: String(l.description ?? ""), amount: Number(l.amount),
    tax_id: (l.tax_id as number | null) ?? null, cost_center_id: (l.cost_center_id as number | null) ?? null, project_id: (l.project_id as number | null) ?? null,
  }));
  removed.value = [];
  closeDetail();
}

const currency = computed(() => String(bank(editor.value?.bank_account_id)?.currency ?? props.base));
const foreign = computed(() => currency.value !== props.base);
watch(
  () => [editor.value?.bank_account_id, editor.value?.txn_date] as const,
  async ([bankId, date], old) => {
    const e = editor.value;
    if (!e || !bankId || !date || !foreign.value || (e.id && old[0] === undefined)) return;
    const { data } = await supabase.rpc("fx_rate_on", { p_currency: currency.value, p_date: date });
    if (data && editor.value === e) e.fx_rate = Number(data);
  },
);

const taxOf = (id: number | null) => taxes.rows.data.value?.find((x) => x.id === id);
function vatOf(l: Line) {
  const tax = taxOf(l.tax_id);
  return tax && l.amount ? round2((round2(l.amount * Number(tax.dpp_factor)) * Number(tax.rate)) / 100) : 0;
}
const previewTotal = computed(() => lines.value.reduce((s, l) => s + (l.amount ?? 0) + vatOf(l), 0));

const saveDraft = useRpcMutation("save_cash_txn_draft", ["t_cash_txns", "t_cash_txn_lines"]);
const removeTxn = useDeleteMasterRow("t_cash_txns");
const REFRESH = ["t_cash_txns", "t_journals", "dashboard_summary", "bank_balances", "cash_month_end", "statement_book_entries"];
const submit = useRpcMutation("submit_cash_txn", REFRESH);
const voidTxn = useRpcMutation("void_cash_txn", REFRESH);
const saving = ref(false);

async function postDoc(id: number) {
  const status = await submit.mutateAsync({ p_id: id });
  toast.success(status === "submitted" ? t("cash.txn.waitingApproval") : t("cash.txn.postedOk"));
}

async function save(post: boolean) {
  const e = editor.value;
  if (!e) return;
  const header = {
    bank_account_id: e.bank_account_id, txn_date: e.txn_date, partner_id: e.partner_id, payee: e.payee.trim() || null,
    fx_rate: foreign.value ? e.fx_rate : 1, reference: e.reference.trim() || null, description: e.description.trim() || null,
    tax_invoice_no: e.tax_invoice_no.trim() || null, tax_invoice_date: e.tax_invoice_date || null,
  };
  const rows = lines.value.map((l) => ({
    account_id: l.account_id, description: l.description.trim() || null, amount: l.amount, tax_id: l.tax_id,
    cost_center_id: l.cost_center_id, project_id: l.project_id,
  }));
  saving.value = true;
  try {
    const id = await saveDraft.mutateAsync({
      p_id: e.id, p_header: e.id ? header : { ...header, direction: e.direction }, p_lines: rows,
    });
    editor.value = null;
    if (post) await postDoc(id);
    else toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    saving.value = false;
  }
}

const formEl = ref<HTMLFormElement | null>(null);
async function postFromDetail(id: number) {
  try {
    await postDoc(id);
    closeDetail();
  } catch (err) {
    toast.error(serverError(err));
  }
}

const deleting = ref<MasterRow | null>(null);
const voiding = ref(false);
async function confirmDelete() {
  const r = deleting.value!;
  if (await run(() => removeTxn.mutateAsync(r.id), t("cash.deleted"))) {
    deleting.value = null;
    closeDetail();
  }
}
async function confirmVoid(reason: string) {
  if (await run(() => voidTxn.mutateAsync({ p_id: detail.value!.id, p_reason: reason }), t("cash.voided"))) voiding.value = false;
}
const lineTotal = (l: MasterRow) => Number(l.amount) + Number(l.tax_amount);
</script>

<template>
  <DocTable
    :title="t('cash.tabs.txns')"
    :columns="[t('cash.docNo'), t('common.date'), t('cash.txn.direction'), t('cash.txn.bank'), t('cash.txn.payee'), t('common.description'), t('common.total'), t('common.status'), '']"
    :rows="txns.data.value ?? []"
    :pending="txns.isPending.value"
    :failed="txns.isError.value"
    :status-label="(s: string) => t(`status.${s}`)"
    @retry="txns.refetch()"
  >
    <template #toolbar>
      <template v-if="can('cash-bank', 'create')">
        <Button size="sm" variant="outline" @click="startNew('in')"><ArrowDownLeft /> {{ t("cash.txn.newIn") }}</Button>
        <Button size="sm" @click="startNew('out')"><ArrowUpRight /> {{ t("cash.txn.newOut") }}</Button>
      </template>
    </template>
    <template #row="{ row }">
      <td class="font-mono text-xs whitespace-nowrap">{{ docNo(row) }}</td>
      <td class="whitespace-nowrap">{{ formatDate(row.txn_date as string) }}</td>
      <td>
        <StatusBadge :tone="row.direction === 'in' ? 'success' : 'danger'">{{ t(`cash.txn.${row.direction}`) }}</StatusBadge>
      </td>
      <td>{{ bank(row.bank_account_id)?.name }}</td>
      <td>{{ partner(row.partner_id)?.name ?? row.payee }}</td>
      <td class="max-w-64 truncate">{{ row.description }}</td>
      <td class="text-right whitespace-nowrap tabular-nums" :class="row.direction === 'in' ? 'text-success' : 'text-rose-600'">
        {{ formatMoney(row.total, String(row.currency)) }}
      </td>
      <td><DocStatus :status="String(row.status)" /></td>
      <td>
        <div class="flex justify-end">
          <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="detailId = row.id"><Info /></Button>
        </div>
      </td>
    </template>
  </DocTable>

  <Dialog :open="!!detail" @update:open="(v) => !v && closeDetail()">
    <DialogContent v-if="detail" class="sm:max-w-3xl">
      <DialogHeader>
        <DialogTitle class="flex flex-wrap items-center gap-2">
          <span class="font-mono">{{ docNo(detail) }}</span>
          <StatusBadge :tone="detail.direction === 'in' ? 'success' : 'danger'">{{ t(`cash.txn.${detail.direction}`) }}</StatusBadge>
          <DocStatus :status="String(detail.status)" />
        </DialogTitle>
        <DialogDescription>{{ detail.description }}</DialogDescription>
      </DialogHeader>
      <div class="max-h-[65vh] space-y-4 overflow-y-auto">
        <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
          <div><dt class="text-muted-foreground text-xs">{{ t("common.date") }}</dt><dd>{{ formatDate(detail.txn_date as string) }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("cash.txn.bank") }}</dt><dd>{{ bank(detail.bank_account_id)?.name }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("cash.txn.payee") }}</dt><dd>{{ partner(detail.partner_id)?.name ?? detail.payee ?? "-" }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("common.reference") }}</dt><dd>{{ detail.reference ?? "-" }}</dd></div>
          <div v-if="detail.tax_invoice_no"><dt class="text-muted-foreground text-xs">{{ t("invoices.taxInvoiceNo") }}</dt><dd class="font-mono text-xs">{{ detail.tax_invoice_no }}</dd></div>
          <div v-if="detail.currency !== base"><dt class="text-muted-foreground text-xs">{{ t("common.rate") }}</dt><dd class="tabular-nums">{{ formatRate(detail.fx_rate) }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("common.total") }}</dt><dd class="font-semibold tabular-nums">{{ formatMoney(detail.total, String(detail.currency)) }}</dd></div>
        </dl>
        <p v-if="detail.reject_reason && detail.status === 'draft'" class="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700 dark:bg-rose-500/10 dark:text-rose-300">
          {{ t("cash.rejected") }}: {{ detail.reject_reason }}
        </p>
        <p v-if="detail.void_reason" class="text-muted-foreground text-sm">{{ t("cash.voidReason") }}: {{ detail.void_reason }}</p>
        <div class="overflow-x-auto rounded-lg border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="px-3 py-2 font-medium">{{ t("common.account") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.description") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.amount") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("cash.txn.vat") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.total") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="l in detailLines.data.value ?? []" :key="l.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                <td><span class="font-mono text-xs">{{ account(l.account_id)?.code }}</span> {{ account(l.account_id)?.name }}</td>
                <td>{{ l.description }}</td>
                <td class="text-right tabular-nums">{{ formatMoney(l.amount, String(detail.currency)) }}</td>
                <td class="text-right tabular-nums">{{ Number(l.tax_amount) ? formatMoney(l.tax_amount, String(detail.currency)) : "-" }}</td>
                <td class="text-right tabular-nums">{{ formatMoney(lineTotal(l), String(detail.currency)) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="flex flex-wrap gap-3 text-sm">
          <RouterLink v-if="detail.journal_id" :to="{ path: '/journals', query: { id: String(detail.journal_id) } }" class="text-primary-text inline-flex items-center gap-1.5 hover:underline">
            <BookOpen class="size-4" /> {{ t("common.openJournal") }}
          </RouterLink>
          <RouterLink v-if="detail.void_journal_id" :to="{ path: '/journals', query: { id: String(detail.void_journal_id) } }" class="text-primary-text inline-flex items-center gap-1.5 hover:underline">
            <Undo2 class="size-4" /> {{ t("cash.voidJournal") }}
          </RouterLink>
        </div>
      </div>
      <DialogFooter class="flex-wrap">
        <template v-if="canEdit(detail)">
          <Button variant="ghost-destructive" @click="deleting = detail"><Trash2 /> {{ t("common.delete") }}</Button>
          <Button variant="outline" :disabled="detailLines.isPending.value" @click="startEdit(detail)"><Pencil /> {{ t("common.edit") }}</Button>
          <Button class="active:scale-95" :disabled="submit.isPending.value" :loading="submit.isPending.value" @click="postFromDetail(detail.id)">
            <Send /> {{ t("cash.post") }}
          </Button>
        </template>
        <Button v-if="detail.status === 'posted' && can('cash-bank', 'delete')" variant="destructive" @click="voiding = true"><X /> {{ t("common.void") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <Dialog :open="!!editor" @update:open="(v) => !v && (editor = null)">
    <DialogContent v-if="editor" class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle>{{ editor.id ? t("cash.txn.edit") : t(editor.direction === "in" ? "cash.txn.newIn" : "cash.txn.newOut") }}</DialogTitle>
        <DialogDescription>{{ t(editor.direction === "in" ? "cash.txn.inHint" : "cash.txn.outHint") }}</DialogDescription>
      </DialogHeader>
      <form id="cash-form" ref="formEl" class="max-h-[70vh] space-y-4 overflow-y-auto p-1" @submit.prevent="save(false)">
        <div class="grid gap-3 sm:grid-cols-3">
          <div class="space-y-1.5">
            <Label for="cash-bank">{{ t("cash.txn.bank") }}</Label>
            <AppSelect id="cash-bank" v-model="editor.bank_account_id" :options="banks.options.value" :placeholder="t('common.pick')" required />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-date">{{ t("common.date") }}</Label>
            <input id="cash-date" v-model="editor.txn_date" type="date" required :class="FIELD_CLASS" />
          </div>
          <div v-if="foreign" class="space-y-1.5">
            <Label for="cash-rate">{{ t("common.rate") }} ({{ currency }} → {{ base }})</Label>
            <input id="cash-rate" v-model.number="editor.fx_rate" type="number" step="0.000001" min="0.000001" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-partner">{{ t("common.partner") }}</Label>
            <SearchSelect id="cash-partner" v-model="editor.partner_id" :options="partners.options.value" null-label="-" />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-payee">{{ t(editor.direction === "in" ? "cash.txn.payer" : "cash.txn.payee") }}</Label>
            <input id="cash-payee" v-model="editor.payee" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-ref">{{ t("common.reference") }}</Label>
            <input id="cash-ref" v-model="editor.reference" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-fp">{{ t("invoices.taxInvoiceNo") }}</Label>
            <input id="cash-fp" v-model="editor.tax_invoice_no" :class="[FIELD_CLASS, 'font-mono']" />
          </div>
          <div class="space-y-1.5">
            <Label for="cash-fpd">{{ t("invoices.taxInvoiceDate") }}</Label>
            <input id="cash-fpd" v-model="editor.tax_invoice_date" type="date" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5 sm:col-span-3">
            <Label for="cash-desc">{{ t("common.description") }}</Label>
            <input id="cash-desc" v-model="editor.description" :class="FIELD_CLASS" />
          </div>
        </div>

        <div class="space-y-2">
          <h3 class="text-sm font-semibold">{{ t("common.lines") }}</h3>
          <div v-for="(l, i) in lines" :key="i" class="grid gap-2 rounded-lg border border-dashed p-3 sm:grid-cols-12">
            <SearchSelect v-model="l.account_id" :options="accountOptions" :aria-label="t('common.account')" :placeholder="t('common.account')" required class="sm:col-span-4" />
            <input v-model="l.description" :placeholder="t('common.description')" :aria-label="t('common.description')" :class="[FIELD_CLASS, 'sm:col-span-5']" />
            <AmountInput v-model="l.amount" :currency="currency" :base="base" :aria-label="t('common.amount')" required class="sm:col-span-3" />
            <AppSelect v-model="l.tax_id" :options="taxes.options.value" :null-label="t('cash.txn.noVat')" :aria-label="t('cash.txn.vat')" class="sm:col-span-3" />
            <AppSelect v-model="l.cost_center_id" :options="costCenters.options.value" :null-label="`${t('common.costCenter')}: -`" :aria-label="t('common.costCenter')" class="sm:col-span-3" />
            <AppSelect v-model="l.project_id" :options="projects.options.value" :null-label="`${t('common.project')}: -`" :aria-label="t('common.project')" class="sm:col-span-3" />
            <div class="flex items-center justify-end gap-2 sm:col-span-3">
              <span v-if="vatOf(l)" class="text-muted-foreground text-xs tabular-nums">{{ t("cash.txn.vat") }} {{ formatMoney(vatOf(l), currency) }}</span>
              <Button
                type="button"
                variant="ghost-destructive"
                size="icon"
                class="size-8"
                :disabled="lines.length === 1"
                :tooltip="t('common.delete')"
                @click="(l.id && removed.push(l.id), lines.splice(i, 1))"
              >
                <Trash2 />
              </Button>
            </div>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <Button type="button" variant="outline" size="sm" @click="lines.push(blankLine())"><Plus /> {{ t("common.addLine") }}</Button>
            <p class="text-sm">
              <span class="text-muted-foreground">{{ t("cash.txn.estimatedTotal") }}</span>
              <span class="ml-2 font-semibold tabular-nums">{{ formatMoney(round2(previewTotal), currency) }}</span>
            </p>
          </div>
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="editor = null">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="cash-form" variant="outline" :disabled="saving" :loading="saving"><Save /> {{ t("cash.saveDraft") }}</Button>
        <Button class="active:scale-95" :disabled="saving" :loading="saving" @click="formEl?.reportValidity() && save(true)">
          <Send /> {{ t("cash.saveAndPost") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <ConfirmDialog
    :open="!!deleting"
    :title="t('common.deleteTitle')"
    :description="t('common.deleteBody')"
    :confirm-label="t('common.delete')"
    :busy="removeTxn.isPending.value"
    destructive
    @update:open="deleting = null"
    @confirm="confirmDelete"
  />
  <ReasonDialog
    v-model:open="voiding"
    :title="t('cash.voidTitle')"
    :description="t('cash.voidBody')"
    :confirm-label="t('common.void')"
    :busy="voidTxn.isPending.value"
    destructive
    @confirm="confirmVoid"
  />
</template>
