<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ArrowRight, BookOpen, Pencil, Plus, Save, Send, Trash2, X } from "@lucide/vue";
import AmountInput from "@/components/cash/AmountInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import ReasonDialog from "@/components/common/ReasonDialog.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useBankOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, useSaveMasterRow, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { useAuthStore } from "@/stores/auth";

const props = defineProps<{ base: string }>();
const { t } = useI18n();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const transfers = useMasterRows("t_bank_transfers", { descending: true });
const banks = useBankOptions();
const bank = (id: unknown) => banks.rows.data.value?.find((b) => b.id === id);
const cur = (id: unknown) => String(bank(id)?.currency ?? props.base);
const docNo = (r: MasterRow) => (r.doc_no as string | null) ?? `${t("cash.draftNo")}${r.id}`;
const mine = (r: MasterRow) => r.created_by === auth.user?.id;
const canEdit = (r: MasterRow) => r.status === "draft" && (can("cash-bank", "update") || (mine(r) && can("cash-bank", "create")));
const canDelete = (r: MasterRow) => r.status === "draft" && (can("cash-bank", "delete") || mine(r));

interface Form { id?: number; transfer_date: string; from_bank_id: number | null; to_bank_id: number | null; from_amount: number | null; to_amount: number | null; from_rate: number | null; to_rate: number | null; fee_amount: number | null; reference: string; note: string }
const form = ref<Form | null>(null);
function start(r?: MasterRow) {
  form.value = r
    ? {
        id: r.id, transfer_date: String(r.transfer_date), from_bank_id: r.from_bank_id as number, to_bank_id: r.to_bank_id as number,
        from_amount: Number(r.from_amount), to_amount: Number(r.to_amount), from_rate: Number(r.from_rate), to_rate: Number(r.to_rate),
        fee_amount: Number(r.fee_amount), reference: String(r.reference ?? ""), note: String(r.note ?? ""),
      }
    : { transfer_date: isoDate(), from_bank_id: null, to_bank_id: null, from_amount: null, to_amount: null, from_rate: 1, to_rate: 1, fee_amount: null, reference: "", note: "" };
}

const fromCur = computed(() => cur(form.value?.from_bank_id));
const toCur = computed(() => cur(form.value?.to_bank_id));
const sameCurrency = computed(() => fromCur.value === toCur.value);
watch(
  () => [form.value?.from_amount, sameCurrency.value] as const,
  ([amount, same]) => {
    if (form.value && same) form.value.to_amount = amount ?? null;
  },
);
async function rateFor(currency: string, date: string) {
  if (currency === props.base) return 1;
  const { data } = await supabase.rpc("fx_rate_on", { p_currency: currency, p_date: date });
  return data ? Number(data) : null;
}
watch(
  () => [form.value?.from_bank_id, form.value?.to_bank_id, form.value?.transfer_date] as const,
  async ([from, to, date], old) => {
    const f = form.value;
    if (!f || !date || (f.id && old[0] === undefined)) return;
    const [a, b] = await Promise.all([rateFor(fromCur.value, date), rateFor(toCur.value, date)]);
    if (form.value !== f) return;
    if (from) f.from_rate = a;
    if (to) f.to_rate = sameCurrency.value ? a : b;
  },
);

const saveRow = useSaveMasterRow("t_bank_transfers");
const removeRow = useDeleteMasterRow("t_bank_transfers");
const REFRESH = ["t_bank_transfers", "t_journals", "dashboard_summary", "bank_balances", "cash_month_end", "statement_book_entries"];
const post = useRpcMutation("post_transfer", REFRESH);
const voidRow = useRpcMutation("void_transfer", REFRESH);

async function save(andPost: boolean) {
  const f = form.value!;
  const values = {
    transfer_date: f.transfer_date, from_bank_id: f.from_bank_id, to_bank_id: f.to_bank_id, from_amount: f.from_amount,
    to_amount: sameCurrency.value ? f.from_amount : f.to_amount, from_rate: fromCur.value === props.base ? 1 : f.from_rate,
    to_rate: toCur.value === props.base ? 1 : sameCurrency.value ? f.from_rate : f.to_rate, fee_amount: f.fee_amount ?? 0,
    reference: f.reference.trim() || null, note: f.note.trim() || null,
  };
  try {
    let id = f.id;
    if (id) await saveRow.mutateAsync({ id, values });
    else {
      const { data, error } = await supabase.from("t_bank_transfers").insert(values as never).select("id").single();
      if (error) throw error;
      id = data.id;
    }
    form.value = null;
    if (andPost) await post.mutateAsync({ p_id: id! });
    else await transfers.refetch();
    toast.success(andPost ? t("cash.transfer.postedOk") : t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
    void transfers.refetch();
  }
}
const formEl = ref<HTMLFormElement | null>(null);

const run = async (action: () => Promise<unknown>, done: string) => {
  try {
    await action();
    toast.success(done);
    return true;
  } catch (err) {
    toast.error(serverError(err));
    return false;
  }
};
const deleting = ref<MasterRow | null>(null);
const voiding = ref<MasterRow | null>(null);
</script>

<template>
  <DocTable
    :title="t('cash.tabs.transfers')"
    :columns="[t('cash.docNo'), t('common.date'), t('cash.transfer.route'), t('cash.transfer.fromAmount'), t('cash.transfer.toAmount'), t('cash.transfer.fee'), t('common.status'), '']"
    :rows="transfers.data.value ?? []"
    :pending="transfers.isPending.value"
    :failed="transfers.isError.value"
    :status-label="(s: string) => t(`status.${s}`)"
    @retry="transfers.refetch()"
  >
    <template #toolbar>
      <Button v-if="can('cash-bank', 'create')" size="sm" @click="start()"><Plus /> {{ t("cash.transfer.new") }}</Button>
    </template>
    <template #row="{ row }">
      <td class="font-mono text-xs whitespace-nowrap">{{ docNo(row) }}</td>
      <td class="whitespace-nowrap">{{ formatDate(row.transfer_date as string) }}</td>
      <td>
        <span class="inline-flex flex-wrap items-center gap-1">{{ bank(row.from_bank_id)?.name }} <ArrowRight class="text-muted-foreground size-3.5" /> {{ bank(row.to_bank_id)?.name }}</span>
        <p v-if="row.note" class="text-muted-foreground max-w-64 truncate text-xs">{{ row.note }}</p>
      </td>
      <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(row.from_amount, cur(row.from_bank_id)) }}</td>
      <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(row.to_amount, cur(row.to_bank_id)) }}</td>
      <td class="text-right whitespace-nowrap tabular-nums">{{ Number(row.fee_amount) ? formatMoney(row.fee_amount, cur(row.from_bank_id)) : "-" }}</td>
      <td><DocStatus :status="String(row.status)" /></td>
      <td>
        <div class="flex justify-end gap-1">
          <RouterLink v-if="row.journal_id" v-slot="{ navigate }" :to="{ path: '/journals', query: { id: String(row.journal_id) } }" custom>
            <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.openJournal')" @click="navigate"><BookOpen /></Button>
          </RouterLink>
          <template v-if="canEdit(row)">
            <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="start(row)"><Pencil /></Button>
            <Button
              variant="soft"
              size="icon"
              class="size-8"
              :disabled="post.isPending.value"
              :tooltip="t('cash.post')"
              @click="run(() => post.mutateAsync({ p_id: row.id }), t('cash.transfer.postedOk'))"
            >
              <Send />
            </Button>
          </template>
          <Button v-if="canDelete(row)" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
          <Button v-if="row.status === 'posted' && can('cash-bank', 'delete')" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.void')" @click="voiding = row"><X /></Button>
        </div>
      </td>
    </template>
  </DocTable>

  <Dialog :open="!!form" @update:open="(v) => !v && (form = null)">
    <DialogContent v-if="form" class="sm:max-w-2xl">
      <DialogHeader>
        <DialogTitle>{{ form.id ? t("cash.transfer.edit") : t("cash.transfer.new") }}</DialogTitle>
        <DialogDescription>{{ t("cash.transfer.hint") }}</DialogDescription>
      </DialogHeader>
      <form id="transfer-form" ref="formEl" class="grid max-h-[70vh] gap-3 overflow-y-auto p-1 sm:grid-cols-2" @submit.prevent="save(false)">
        <div class="space-y-1.5">
          <Label for="trf-date">{{ t("common.date") }}</Label>
          <input id="trf-date" v-model="form.transfer_date" type="date" required :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-ref">{{ t("common.reference") }}</Label>
          <input id="trf-ref" v-model="form.reference" :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-from">{{ t("cash.transfer.from") }}</Label>
          <AppSelect id="trf-from" v-model="form.from_bank_id" :options="banks.options.value.filter((o) => o.value !== form!.to_bank_id)" :placeholder="t('common.pick')" required />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-to">{{ t("cash.transfer.to") }}</Label>
          <AppSelect id="trf-to" v-model="form.to_bank_id" :options="banks.options.value.filter((o) => o.value !== form!.from_bank_id)" :placeholder="t('common.pick')" required />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-from-amount">{{ t("cash.transfer.fromAmount") }}</Label>
          <AmountInput id="trf-from-amount" v-model="form.from_amount" :currency="fromCur" :base="base" required />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-to-amount">{{ t("cash.transfer.toAmount") }}</Label>
          <AmountInput id="trf-to-amount" v-model="form.to_amount" :currency="toCur" :base="base" required :disabled="sameCurrency" />
        </div>
        <div v-if="fromCur !== base" class="space-y-1.5">
          <Label for="trf-from-rate">{{ t("cash.transfer.fromRate") }} ({{ fromCur }} → {{ base }})</Label>
          <input id="trf-from-rate" v-model.number="form.from_rate" type="number" step="0.000001" min="0.000001" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
        </div>
        <div v-if="toCur !== base && !sameCurrency" class="space-y-1.5">
          <Label for="trf-to-rate">{{ t("cash.transfer.toRate") }} ({{ toCur }} → {{ base }})</Label>
          <input id="trf-to-rate" v-model.number="form.to_rate" type="number" step="0.000001" min="0.000001" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
        </div>
        <div class="space-y-1.5">
          <Label for="trf-fee">{{ t("cash.transfer.fee") }}</Label>
          <AmountInput id="trf-fee" v-model="form.fee_amount" :currency="fromCur" :base="base" />
          <p class="text-muted-foreground text-xs">{{ t("cash.transfer.feeHint") }}</p>
        </div>
        <div class="space-y-1.5 sm:col-span-2">
          <Label for="trf-note">{{ t("common.note") }}</Label>
          <input id="trf-note" v-model="form.note" :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="form = null">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="transfer-form" variant="outline" :disabled="saveRow.isPending.value || post.isPending.value"><Save /> {{ t("cash.saveDraft") }}</Button>
        <Button class="active:scale-95" :disabled="saveRow.isPending.value || post.isPending.value" :loading="post.isPending.value" @click="formEl?.reportValidity() && save(true)">
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
    :busy="removeRow.isPending.value"
    destructive
    @update:open="deleting = null"
    @confirm="run(() => removeRow.mutateAsync(deleting!.id), t('cash.deleted')).then((ok) => ok && (deleting = null))"
  />
  <ReasonDialog
    :open="!!voiding"
    :title="t('cash.voidTitle')"
    :description="t('cash.voidBody')"
    :confirm-label="t('common.void')"
    :busy="voidRow.isPending.value"
    destructive
    @update:open="(v) => !v && (voiding = null)"
    @confirm="(reason) => run(() => voidRow.mutateAsync({ p_id: voiding!.id, p_reason: reason }), t('cash.voided')).then((ok) => ok && (voiding = null))"
  />
</template>
