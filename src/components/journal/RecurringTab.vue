<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Pencil, Play, Plus, Save, Trash2 } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocTable from "@/components/common/DocTable.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import JournalLinesEditor from "@/components/journal/JournalLinesEditor.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { blankLine, filledLines, lineTotals, toLine, type JournalLine } from "./lines";

const emit = defineEmits<{ openJournal: [id: number] }>();
const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const rows = useMasterRows("t_recurring_journals", { columns: "*, last:t_journals!t_recurring_journals_last_journal_id_fkey(doc_no)", order: "next_run" });
const remove = useDeleteMasterRow("t_recurring_journals");
const saveRecurring = useRpcMutation("save_recurring_journal", ["t_recurring_journals", "t_recurring_journal_lines"]);
const run = useRpcMutation("run_recurring_journals", ["t_journals", "t_recurring_journals", "general_ledger", "trial_balance", "period_checklist"]);
const FREQS = computed(() => ["monthly", "quarterly", "yearly"].map((f) => ({ value: f, label: t(`journals.recurring.frequencies.${f}`) })));

const editOpen = ref(false);
const editing = ref<MasterRow | null>(null);
const form = ref({ name: "", memo: "", frequency: "monthly", next_run: isoDate(), end_date: "", is_active: true });
const lines = ref<JournalLine[]>([]);
const loading = ref(false);
const busy = ref(false);
const totals = computed(() => lineTotals(lines.value));

async function openEditor(row: MasterRow | null) {
  editing.value = row;
  form.value = {
    name: (row?.name as string) ?? "",
    memo: (row?.memo as string) ?? "",
    frequency: (row?.frequency as string) ?? "monthly",
    next_run: (row?.next_run as string) ?? isoDate(),
    end_date: (row?.end_date as string) ?? "",
    is_active: (row?.is_active as boolean) ?? true,
  };
  lines.value = [blankLine(), blankLine()];
  editOpen.value = true;
  if (!row) return;
  loading.value = true;
  const { data, error } = await supabase.from("t_recurring_journal_lines").select("*").eq("recurring_id", row.id).order("id");
  loading.value = false;
  if (error) return toast.error(serverError(error));
  if (data.length) lines.value = data.map(toLine);
}

async function save() {
  if (totals.value.diff !== 0 || totals.value.debit === 0) return;
  busy.value = true;
  try {
    const header = { ...form.value, memo: form.value.memo.trim() || null, end_date: form.value.end_date || null };
    await saveRecurring.mutateAsync({ p_id: editing.value?.id, p_header: header, p_lines: filledLines(lines.value) });
    toast.success(t("common.saved"));
    editOpen.value = false;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    busy.value = false;
  }
}

const deleting = ref<MasterRow | null>(null);
async function confirmDelete() {
  try {
    await remove.mutateAsync(deleting.value!.id);
    deleting.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}

const runOpen = ref(false);
async function runDue() {
  try {
    const n = await run.mutateAsync({ p_as_of: isoDate() });
    runOpen.value = false;
    toast.success(n ? t("journals.recurring.runResult", { n }) : t("journals.recurring.runNone"));
  } catch (err) {
    toast.error(serverError(err));
  }
}
const isDue = (r: MasterRow) => r.is_active && String(r.next_run) <= isoDate() && (!r.end_date || String(r.next_run) <= String(r.end_date));
</script>

<template>
  <DocTable
    :title="t('journals.recurring.title')"
    :columns="[t('journals.recurring.name'), t('journals.recurring.frequency'), t('journals.recurring.nextRun'), t('journals.recurring.endDate'), t('journals.recurring.lastJournal'), t('common.status'), '']"
    :rows="rows.data.value ?? []"
    :pending="rows.isPending.value"
    :failed="rows.isError.value"
    @retry="rows.refetch()"
  >
    <template #toolbar>
      <Button v-if="can('journal', 'update')" size="sm" variant="outline" @click="runOpen = true"><Play /> {{ t("journals.recurring.runDue") }}</Button>
      <Button v-if="can('journal', 'update')" size="sm" @click="openEditor(null)"><Plus /> {{ t("journals.recurring.new") }}</Button>
    </template>
    <template #row="{ row }">
      <td>
        <p class="font-medium">{{ row.name }}</p>
        <p v-if="row.memo" class="text-muted-foreground text-xs">{{ row.memo }}</p>
      </td>
      <td>{{ t(`journals.recurring.frequencies.${row.frequency}`) }}</td>
      <td class="whitespace-nowrap tabular-nums" :class="{ 'font-semibold text-rose-700 dark:text-rose-400': isDue(row) }">{{ formatDate(row.next_run as string) }}</td>
      <td class="whitespace-nowrap tabular-nums">{{ formatDate(row.end_date as string) || "-" }}</td>
      <td>
        <button v-if="row.last_journal_id" type="button" class="text-primary-text font-mono text-xs hover:underline" @click="emit('openJournal', row.last_journal_id as number)">
          {{ (row.last as { doc_no?: string } | null)?.doc_no ?? `#${row.last_journal_id}` }}
        </button>
        <span v-else>-</span>
      </td>
      <td><StatusBadge :tone="row.is_active ? 'success' : 'muted'">{{ row.is_active ? t("common.active") : t("common.inactive") }}</StatusBadge></td>
      <td>
        <div class="flex justify-end gap-1">
          <Button v-if="can('journal', 'update')" variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openEditor(row)"><Pencil /></Button>
          <Button v-if="can('journal', 'delete')" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
        </div>
      </td>
    </template>
  </DocTable>

  <Dialog v-model:open="editOpen">
    <DialogContent class="sm:max-w-6xl">
      <DialogHeader>
        <DialogTitle>{{ editing ? t("journals.recurring.edit") : t("journals.recurring.new") }}</DialogTitle>
      </DialogHeader>
      <LoadingState v-if="loading" variant="form" />
      <form v-else id="recurring-form" class="max-h-[70vh] space-y-4 overflow-y-auto p-1" @submit.prevent="save">
        <div class="grid gap-3 sm:grid-cols-4">
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="rj-name">{{ t("journals.recurring.name") }}</Label>
            <input id="rj-name" v-model="form.name" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="rj-memo">{{ t("journals.memo") }}</Label>
            <input id="rj-memo" v-model="form.memo" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="rj-freq">{{ t("journals.recurring.frequency") }}</Label>
            <AppSelect id="rj-freq" :model-value="form.frequency" :options="FREQS" required @update:model-value="form.frequency = $event ?? 'monthly'" />
          </div>
          <div class="space-y-1.5">
            <Label for="rj-next">{{ t("journals.recurring.nextRun") }}</Label>
            <input id="rj-next" v-model="form.next_run" type="date" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="rj-end">{{ t("journals.recurring.endDate") }}</Label>
            <input id="rj-end" v-model="form.end_date" type="date" :min="form.next_run" :class="FIELD_CLASS" />
            <p class="text-muted-foreground text-xs">{{ t("journals.recurring.endDateHint") }}</p>
          </div>
          <label class="flex items-center gap-2 pt-6 text-sm">
            <input v-model="form.is_active" type="checkbox" class="accent-primary size-4" /> {{ t("common.active") }}
          </label>
        </div>
        <JournalLinesEditor v-model="lines" />
        <p v-if="totals.diff !== 0" class="rounded-lg bg-rose-500/10 px-3 py-2 text-sm text-rose-700 dark:text-rose-400">
          {{ t("journals.recurring.unbalanced", { amount: formatMoney(Math.abs(totals.diff)) }) }}
        </p>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="editOpen = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="recurring-form" class="active:scale-95" :disabled="busy || loading || totals.diff !== 0 || totals.debit === 0" :loading="busy">
          <Save /> {{ t("common.save") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <ConfirmDialog
    v-model:open="runOpen"
    :title="t('journals.recurring.runDue')"
    :description="t('journals.recurring.runDueBody')"
    :confirm-label="t('journals.recurring.runDue')"
    :busy="run.isPending.value"
    @confirm="runDue"
  />
  <ConfirmDialog
    :open="!!deleting"
    :title="t('common.deleteTitle')"
    :description="t('common.deleteBody')"
    :confirm-label="t('common.delete')"
    :busy="remove.isPending.value"
    destructive
    @update:open="deleting = null"
    @confirm="confirmDelete"
  />
</template>
