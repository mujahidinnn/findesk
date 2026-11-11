<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { FolderOpen, Plus, Save, Trash2 } from "@lucide/vue";
import AmountInput from "@/components/cash/AmountInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import StatementWorkspace from "@/components/reconcile/StatementWorkspace.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useBankOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { useSettings } from "@/composables/useSettings";
import { supabase } from "@/integrations/supabase/client";
import { useQueryClient } from "@tanstack/vue-query";
import { formatAmount, formatDate, isoDate, monthEnd, monthStart } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const qc = useQueryClient();
const { can } = usePermissions();
const serverError = useServerError();
const settings = useSettings();
const base = computed(() => settings.data.value?.base_currency ?? "IDR");

const statements = useMasterRows("t_bank_statements", { descending: true });
// ponytail: match counts come from one 1000-row read of statement lines; move to a view if statements grow past that.
const lineStats = useMasterRows("t_bank_statement_lines", { columns: "id, statement_id, journal_line_id" });
const banks = useBankOptions();
const bank = (id: unknown) => banks.rows.data.value?.find((b) => b.id === id);
const bankFilter = ref<number | null>(null);
const rows = computed(() => (statements.data.value ?? []).filter((s) => !bankFilter.value || s.bank_account_id === bankFilter.value));
const stats = computed(() => {
  const map = new Map<number, { total: number; matched: number }>();
  for (const l of lineStats.data.value ?? []) {
    const s = map.get(l.statement_id as number) ?? { total: 0, matched: 0 };
    s.total++;
    if (l.journal_line_id) s.matched++;
    map.set(l.statement_id as number, s);
  }
  return map;
});

const openId = computed(() => Number(route.query.id) || null);
const current = computed(() => statements.data.value?.find((s) => s.id === openId.value) ?? null);
const openStatement = (id: number | null) => router.replace({ query: { ...route.query, id: id ? String(id) : undefined } });

interface Form { bank_account_id: number | null; start_date: string; statement_date: string; opening_balance: number | null; closing_balance: number | null; note: string }
const form = ref<Form | null>(null);
const saving = ref(false);
function start() {
  form.value = { bank_account_id: bankFilter.value, start_date: monthStart(), statement_date: monthEnd(), opening_balance: null, closing_balance: null, note: "" };
  if (bankFilter.value) continueFrom(bankFilter.value);
}
function continueFrom(bankId: number | null) {
  if (!form.value) return;
  form.value.bank_account_id = bankId;
  const last = (statements.data.value ?? []).filter((s) => s.bank_account_id === bankId).sort((a, b) => String(b.statement_date).localeCompare(String(a.statement_date)))[0];
  if (!last) return;
  const next = new Date(`${last.statement_date}T00:00`);
  next.setDate(next.getDate() + 1);
  form.value.start_date = isoDate(next);
  form.value.statement_date = monthEnd(next);
  form.value.opening_balance = Number(last.closing_balance);
}
const formCurrency = computed(() => String(bank(form.value?.bank_account_id)?.currency ?? base.value));
async function create() {
  const f = form.value!;
  saving.value = true;
  try {
    const { data, error } = await supabase
      .from("t_bank_statements")
      .insert({
        bank_account_id: f.bank_account_id!, start_date: f.start_date, statement_date: f.statement_date,
        opening_balance: f.opening_balance ?? 0, closing_balance: f.closing_balance ?? 0, note: f.note.trim() || null,
      })
      .select("id")
      .single();
    if (error) throw error;
    await qc.invalidateQueries({ queryKey: ["t_bank_statements"] });
    form.value = null;
    toast.success(t("common.saved"));
    void openStatement(data.id);
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    saving.value = false;
  }
}

const remove = useDeleteMasterRow("t_bank_statements");
const deleting = ref<MasterRow | null>(null);
const canDelete = (s: MasterRow) => s.status === "open" && can("reconcile", "delete") && !stats.value.get(s.id)?.matched;
async function confirmDelete() {
  try {
    await remove.mutateAsync(deleting.value!.id);
    deleting.value = null;
    toast.success(t("reconcile.deleted"));
  } catch (err) {
    toast.error(serverError(err));
  }
}
</script>

<template>
  <StatementWorkspace v-if="current" :statement="current" :bank="bank(current.bank_account_id)" :base="base" @back="openStatement(null)" />
  <template v-else>
    <DocTable
      :title="t('reconcile.title')"
      :columns="[t('reconcile.bank'), t('reconcile.period'), t('reconcile.opening'), t('reconcile.closing'), t('reconcile.matched'), t('common.status'), '']"
      :rows="rows"
      :pending="statements.isPending.value"
      :failed="statements.isError.value"
      :status-label="(s: string) => t(`status.${s}`)"
      @retry="statements.refetch()"
    >
      <template #toolbar>
        <AppSelect v-model="bankFilter" :options="banks.options.value" :null-label="`${t('reconcile.bank')}: ${t('common.all')}`" class="w-48" :aria-label="t('reconcile.bank')" />
        <Button v-if="can('reconcile', 'create')" size="sm" @click="start"><Plus /> {{ t("reconcile.new") }}</Button>
      </template>
      <template #row="{ row }">
        <td>
          <button type="button" class="hover:text-primary-text text-left font-medium hover:underline" @click="openStatement(row.id)">{{ bank(row.bank_account_id)?.name }}</button>
        </td>
        <td class="whitespace-nowrap">{{ formatDate(row.start_date as string) }} – {{ formatDate(row.statement_date as string) }}</td>
        <td class="text-right tabular-nums">{{ formatAmount(row.opening_balance) }}</td>
        <td class="text-right tabular-nums">{{ formatAmount(row.closing_balance) }}</td>
        <td class="tabular-nums">{{ stats.get(row.id)?.matched ?? 0 }}/{{ stats.get(row.id)?.total ?? 0 }}</td>
        <td><DocStatus :status="String(row.status)" /></td>
        <td>
          <div class="flex justify-end gap-1">
            <Button variant="ghost" size="icon" class="size-8" :tooltip="t('reconcile.open')" @click="openStatement(row.id)"><FolderOpen /></Button>
            <Button v-if="canDelete(row)" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
          </div>
        </td>
      </template>
    </DocTable>
  </template>

  <Dialog :open="!!form" @update:open="(v) => !v && (form = null)">
    <DialogContent v-if="form" class="sm:max-w-lg">
      <DialogHeader>
        <DialogTitle>{{ t("reconcile.new") }}</DialogTitle>
        <DialogDescription>{{ t("reconcile.newHint") }}</DialogDescription>
      </DialogHeader>
      <form id="statement-form" class="grid gap-3 sm:grid-cols-2" @submit.prevent="create">
        <div class="space-y-1.5 sm:col-span-2">
          <Label for="st-bank">{{ t("reconcile.bank") }}</Label>
          <AppSelect id="st-bank" :model-value="form.bank_account_id" :options="banks.options.value" :placeholder="t('common.pick')" required @update:model-value="continueFrom" />
        </div>
        <div class="space-y-1.5">
          <Label for="st-start">{{ t("reconcile.startDate") }}</Label>
          <input id="st-start" v-model="form.start_date" type="date" required :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="st-end">{{ t("reconcile.statementDate") }}</Label>
          <input id="st-end" v-model="form.statement_date" type="date" :min="form.start_date" required :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="st-open">{{ t("reconcile.opening") }}</Label>
          <AmountInput id="st-open" v-model="form.opening_balance" :currency="formCurrency" :base="base" negative required />
        </div>
        <div class="space-y-1.5">
          <Label for="st-close">{{ t("reconcile.closing") }}</Label>
          <AmountInput id="st-close" v-model="form.closing_balance" :currency="formCurrency" :base="base" negative required />
        </div>
        <div class="space-y-1.5 sm:col-span-2">
          <Label for="st-note">{{ t("common.note") }}</Label>
          <input id="st-note" v-model="form.note" :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="form = null">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="statement-form" :disabled="saving" :loading="saving"><Save /> {{ t("common.save") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <ConfirmDialog
    :open="!!deleting"
    :title="t('common.deleteTitle')"
    :description="t('reconcile.deleteBody')"
    :confirm-label="t('common.delete')"
    :busy="remove.isPending.value"
    destructive
    @update:open="deleting = null"
    @confirm="confirmDelete"
  />
</template>
