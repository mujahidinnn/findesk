<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { useQueryClient } from "@tanstack/vue-query";
import { ArrowLeft, BookPlus, CheckCheck, Link2, Plus, Save, Trash2, Unlink, Upload, Wand2, LockOpen } from "@lucide/vue";
import AmountInput from "@/components/cash/AmountInput.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useAccountOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { parseBankCsv } from "@/lib/bankCsv";
import { formatAmount, formatDate, round2 } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const props = defineProps<{ statement: MasterRow; bank?: MasterRow; base: string }>();
defineEmits<{ back: [] }>();
const { t } = useI18n();
const qc = useQueryClient();
const { can } = usePermissions();
const serverError = useServerError();

const id = computed(() => props.statement.id);
const currency = computed(() => String(props.bank?.currency ?? props.base));
const isOpen = computed(() => props.statement.status === "open");
const canLines = computed(() => isOpen.value && can("reconcile", "create"));
const canMatch = computed(() => isOpen.value && can("reconcile", "update"));
const canBook = computed(() => canMatch.value && can("cash-bank", "create"));

const lines = useMasterRows("t_bank_statement_lines", { filter: () => ({ statement_id: id.value }), order: "line_date" });
const entries = useRpcQuery("statement_book_entries", () => ({ p_statement_id: id.value }));
const summary = useRpcQuery("dashboard_summary", () => ({ p_from: String(props.statement.start_date), p_to: String(props.statement.statement_date) }));
const bookBalance = computed(() => {
  const b = ((summary.data.value as { banks?: { id: number; base: number; fc: number }[] } | undefined)?.banks ?? []).find((x) => x.id === props.bank?.id);
  return b ? (currency.value === props.base ? b.base : b.fc) : null;
});

const linesSum = computed(() => round2((lines.data.value ?? []).reduce((s, l) => s + Number(l.amount), 0)));
const computedClosing = computed(() => round2(Number(props.statement.opening_balance) + linesSum.value));
const difference = computed(() => round2(Number(props.statement.closing_balance) - computedClosing.value));
const unmatched = computed(() => (lines.data.value ?? []).filter((l) => !l.journal_line_id).length);

const selLine = ref<number | null>(null);
const selEntry = ref<number | null>(null);
watch(id, () => {
  selLine.value = null;
  selEntry.value = null;
});
const selLineAmount = computed(() => Number(lines.data.value?.find((l) => l.id === selLine.value)?.amount ?? NaN));
const selEntryAmount = computed(() => Number(entries.data.value?.find((e) => e.journal_line_id === selEntry.value)?.amount ?? NaN));
const canPair = computed(() => selLine.value != null && selEntry.value != null && selLineAmount.value === selEntryAmount.value);

const REFRESH = ["t_bank_statement_lines", "statement_book_entries"];
const autoMatch = useRpcMutation("auto_match_statement", REFRESH);
const match = useRpcMutation("match_statement_line", REFRESH);
const book = useRpcMutation("book_statement_line", [...REFRESH, "t_cash_txns", "t_journals", "dashboard_summary", "bank_balances", "cash_month_end"]);
const finish = useRpcMutation("finish_statement", ["t_bank_statements"]);
const reopen = useRpcMutation("reopen_statement", ["t_bank_statements"]);
const removeLine = useDeleteMasterRow("t_bank_statement_lines");

const run = async (action: () => Promise<unknown>, done: string | (() => string)) => {
  try {
    await action();
    toast.success(typeof done === "string" ? done : done());
    return true;
  } catch (err) {
    toast.error(serverError(err));
    return false;
  }
};
let matchedCount = 0;
const runAuto = () =>
  run(async () => (matchedCount = await autoMatch.mutateAsync({ p_statement_id: id.value })), () => t("reconcile.autoMatched", { n: matchedCount }));
async function pair() {
  if (await run(() => match.mutateAsync({ p_line_id: selLine.value!, p_journal_line_id: selEntry.value! }), t("reconcile.matchedOk"))) {
    selLine.value = null;
    selEntry.value = null;
  }
}
const unpair = (lineId: number) => run(() => match.mutateAsync({ p_line_id: lineId, p_journal_line_id: null as unknown as number }), t("reconcile.unmatchedOk"));

interface LineForm { line_date: string; direction: "in" | "out"; amount: number | null; description: string; reference: string }
const lineForm = ref<LineForm | null>(null);
const savingLines = ref(false);
async function insertLines(rows: { line_date: string; description: string | null; reference: string | null; amount: number }[]) {
  const { error } = await supabase.from("t_bank_statement_lines").insert(rows.map((r) => ({ ...r, statement_id: id.value })));
  if (error) throw error;
  await qc.invalidateQueries({ queryKey: ["t_bank_statement_lines"] });
}
async function addLine() {
  const f = lineForm.value!;
  savingLines.value = true;
  const ok = await run(
    () => insertLines([{ line_date: f.line_date, description: f.description.trim() || null, reference: f.reference.trim() || null, amount: (f.direction === "in" ? 1 : -1) * (f.amount ?? 0) }]),
    t("common.saved"),
  );
  savingLines.value = false;
  if (ok) lineForm.value = null;
}
const fileInput = ref<HTMLInputElement | null>(null);
async function importCsv(e: Event) {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  input.value = "";
  if (!file) return;
  let parsed: ReturnType<typeof parseBankCsv>;
  try {
    parsed = parseBankCsv(await file.text());
  } catch {
    return void toast.error(t("reconcile.csvInvalid"));
  }
  if (!parsed.lines.length) return void toast.error(t("reconcile.csvNoRows"));
  savingLines.value = true;
  await run(() => insertLines(parsed.lines), t("reconcile.imported", { n: parsed.lines.length, skipped: parsed.skipped }));
  savingLines.value = false;
}

const booking = ref<MasterRow | null>(null);
const bookAccount = ref<number | null>(null);
const bookDescription = ref("");
const accounts = useAccountOptions({ exclude: ["cash", "bank"] });
const accountOptions = computed(() => {
  const control = new Set((accounts.rows.data.value ?? []).filter((a) => a.is_control).map((a) => a.id));
  return accounts.options.value.filter((o) => !control.has(o.value));
});
function startBook(l: MasterRow) {
  booking.value = l;
  bookAccount.value = null;
  bookDescription.value = String(l.description ?? "");
}
async function confirmBook() {
  const ok = await run(
    () => book.mutateAsync({ p_line_id: booking.value!.id, p_account_id: bookAccount.value!, p_description: bookDescription.value.trim() || undefined }),
    t("reconcile.bookedOk"),
  );
  if (ok) booking.value = null;
}

const finishing = ref(false);
const deletingLine = ref<MasterRow | null>(null);
const amountClass = (n: unknown) => (Number(n) > 0 ? "text-success" : "text-rose-600");
</script>

<template>
  <div class="space-y-4">
    <div class="toolbar">
      <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.close')" @click="$emit('back')"><ArrowLeft /></Button>
      <div class="mr-auto min-w-0">
        <h2 class="flex flex-wrap items-center gap-2 font-semibold">{{ bank?.name }} <DocStatus :status="String(statement.status)" /></h2>
        <p class="text-muted-foreground text-xs">{{ formatDate(statement.start_date as string) }} – {{ formatDate(statement.statement_date as string) }} · {{ currency }}</p>
      </div>
      <template v-if="canLines">
        <input ref="fileInput" type="file" accept=".csv,text/csv,text/plain" class="hidden" @change="importCsv" />
        <Button variant="outline" size="sm" :disabled="savingLines" :tooltip="t('reconcile.csvHint')" @click="fileInput?.click()"><Upload /> {{ t("reconcile.importCsv") }}</Button>
        <Button
          variant="outline"
          size="sm"
          @click="lineForm = { line_date: String(statement.statement_date), direction: 'out', amount: null, description: '', reference: '' }"
        >
          <Plus /> {{ t("reconcile.addLine") }}
        </Button>
      </template>
      <Button v-if="canMatch" variant="soft" size="sm" :disabled="autoMatch.isPending.value" :loading="autoMatch.isPending.value" @click="runAuto"><Wand2 /> {{ t("reconcile.autoMatch") }}</Button>
      <Button v-if="canMatch" size="sm" class="active:scale-95" @click="finishing = true"><CheckCheck /> {{ t("reconcile.finish") }}</Button>
      <Button
        v-if="statement.status === 'finished' && can('reconcile', 'delete')"
        variant="outline"
        size="sm"
        :disabled="reopen.isPending.value"
        @click="run(() => reopen.mutateAsync({ p_statement_id: statement.id }), t('reconcile.reopenedOk'))"
      >
        <LockOpen /> {{ t("reconcile.reopen") }}
      </Button>
    </div>

    <dl class="bg-card grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl border p-4 text-sm sm:grid-cols-3 lg:grid-cols-6">
      <div><dt class="text-muted-foreground text-xs">{{ t("reconcile.opening") }}</dt><dd class="font-medium tabular-nums">{{ formatAmount(statement.opening_balance) }}</dd></div>
      <div><dt class="text-muted-foreground text-xs">{{ t("reconcile.movement") }}</dt><dd class="font-medium tabular-nums">{{ formatAmount(linesSum) }}</dd></div>
      <div><dt class="text-muted-foreground text-xs">{{ t("reconcile.computedClosing") }}</dt><dd class="font-medium tabular-nums">{{ formatAmount(computedClosing) }}</dd></div>
      <div><dt class="text-muted-foreground text-xs">{{ t("reconcile.bankBalance") }}</dt><dd class="font-medium tabular-nums">{{ formatAmount(statement.closing_balance) }}</dd></div>
      <div>
        <dt class="text-muted-foreground text-xs">{{ t("reconcile.difference") }}</dt>
        <dd class="font-semibold tabular-nums" :class="difference === 0 ? 'text-success' : 'text-rose-600'">{{ difference === 0 ? t("reconcile.balanced") : formatAmount(difference) }}</dd>
      </div>
      <div>
        <dt class="text-muted-foreground text-xs">{{ t("reconcile.bookBalance") }}</dt>
        <dd class="font-medium tabular-nums">{{ bookBalance == null ? "…" : formatAmount(bookBalance) }}</dd>
      </div>
    </dl>
    <p class="text-muted-foreground text-xs">{{ t("reconcile.unmatchedCount", { n: unmatched, total: lines.data.value?.length ?? 0 }) }}</p>

    <div class="grid gap-4 lg:grid-cols-2">
      <section class="space-y-2">
        <h3 class="text-sm font-semibold">{{ t("reconcile.statementLines") }}</h3>
        <LoadingState v-if="lines.isPending.value" :columns="4" :rows="4" />
        <EmptyState v-else-if="!lines.data.value?.length" compact :title="t('reconcile.noLines')" :description="canLines ? t('reconcile.noLinesHint') : undefined" />
        <div v-else class="bg-card overflow-x-auto rounded-xl border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="w-px px-3 py-2"><span class="sr-only">{{ t("reconcile.select") }}</span></th>
                <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.description") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.amount") }}</th>
                <th class="w-px px-3 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="l in lines.data.value"
                :key="l.id"
                class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2"
                :class="selLine === l.id && 'bg-primary-soft'"
              >
                <td>
                  <input
                    v-if="canMatch && !l.journal_line_id"
                    v-model="selLine"
                    type="radio"
                    name="statement-line"
                    :value="l.id"
                    class="accent-primary size-4"
                    :aria-label="t('reconcile.select')"
                  />
                  <StatusBadge v-else-if="l.journal_line_id" tone="success">{{ t("reconcile.matchedBadge") }}</StatusBadge>
                </td>
                <td class="whitespace-nowrap">{{ formatDate(l.line_date as string) }}</td>
                <td>
                  {{ l.description }}
                  <span v-if="l.reference" class="text-muted-foreground block font-mono text-xs">{{ l.reference }}</span>
                </td>
                <td class="text-right whitespace-nowrap tabular-nums" :class="amountClass(l.amount)">{{ formatAmount(l.amount) }}</td>
                <td>
                  <div class="flex justify-end gap-1">
                    <Button v-if="canMatch && l.journal_line_id" variant="ghost" size="icon" class="size-8" :tooltip="t('reconcile.unmatch')" @click="unpair(l.id)"><Unlink /></Button>
                    <template v-else-if="!l.journal_line_id">
                      <Button v-if="canBook" variant="ghost" size="icon" class="size-8" :tooltip="t('reconcile.book')" @click="startBook(l)"><BookPlus /></Button>
                      <Button v-if="canLines" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deletingLine = l"><Trash2 /></Button>
                    </template>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="space-y-2">
        <div class="flex items-center gap-2">
          <h3 class="mr-auto text-sm font-semibold">{{ t("reconcile.bookEntries") }}</h3>
          <Button v-if="canMatch" size="sm" :disabled="!canPair || match.isPending.value" :loading="match.isPending.value" @click="pair"><Link2 /> {{ t("reconcile.match") }}</Button>
        </div>
        <p v-if="selLine != null && selEntry != null && !canPair" class="text-xs text-rose-600">{{ t("reconcile.amountMismatch") }}</p>
        <LoadingState v-if="entries.isPending.value" :columns="4" :rows="4" />
        <EmptyState v-else-if="entries.isError.value" compact :title="t('common.loadFailed')" />
        <EmptyState v-else-if="!entries.data.value?.length" compact :title="t('reconcile.noEntries')" />
        <div v-else class="bg-card overflow-x-auto rounded-xl border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="w-px px-3 py-2"><span class="sr-only">{{ t("reconcile.select") }}</span></th>
                <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.description") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.amount") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="e in entries.data.value"
                :key="e.journal_line_id"
                class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2"
                :class="[selEntry === e.journal_line_id && 'bg-primary-soft', selLine != null && Number(e.amount) === selLineAmount && selEntry !== e.journal_line_id && 'outline-primary/40 outline-2 -outline-offset-2']"
              >
                <td>
                  <input
                    v-if="canMatch"
                    v-model="selEntry"
                    type="radio"
                    name="book-entry"
                    :value="e.journal_line_id"
                    class="accent-primary size-4"
                    :aria-label="t('reconcile.select')"
                  />
                </td>
                <td class="whitespace-nowrap">{{ formatDate(e.journal_date) }}</td>
                <td>
                  {{ e.memo }}
                  <span class="text-muted-foreground block font-mono text-xs">{{ [e.doc_no, e.reference].filter(Boolean).join(" · ") }}</span>
                </td>
                <td class="text-right whitespace-nowrap tabular-nums" :class="amountClass(e.amount)">{{ formatAmount(e.amount) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>

  <Dialog :open="!!lineForm" @update:open="(v) => !v && (lineForm = null)">
    <DialogContent v-if="lineForm" class="sm:max-w-lg">
      <DialogHeader>
        <DialogTitle>{{ t("reconcile.addLine") }}</DialogTitle>
      </DialogHeader>
      <form id="line-form" class="grid gap-3 sm:grid-cols-2" @submit.prevent="addLine">
        <div class="space-y-1.5">
          <Label for="ln-date">{{ t("common.date") }}</Label>
          <input id="ln-date" v-model="lineForm.line_date" type="date" :min="String(statement.start_date)" :max="String(statement.statement_date)" required :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="ln-dir">{{ t("reconcile.direction") }}</Label>
          <AppSelect
            id="ln-dir"
            :model-value="lineForm.direction"
            :options="[{ value: 'in', label: t('reconcile.moneyIn') }, { value: 'out', label: t('reconcile.moneyOut') }]"
            @update:model-value="(v) => v && (lineForm!.direction = v as 'in' | 'out')"
          />
        </div>
        <div class="space-y-1.5 sm:col-span-2">
          <Label for="ln-amount">{{ t("common.amount") }}</Label>
          <AmountInput id="ln-amount" v-model="lineForm.amount" :currency="currency" :base="base" required />
        </div>
        <div class="space-y-1.5">
          <Label for="ln-desc">{{ t("common.description") }}</Label>
          <input id="ln-desc" v-model="lineForm.description" :class="FIELD_CLASS" />
        </div>
        <div class="space-y-1.5">
          <Label for="ln-ref">{{ t("common.reference") }}</Label>
          <input id="ln-ref" v-model="lineForm.reference" :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="lineForm = null">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="line-form" :disabled="savingLines || !lineForm.amount" :loading="savingLines"><Save /> {{ t("common.save") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <Dialog :open="!!booking" @update:open="(v) => !v && (booking = null)">
    <DialogContent v-if="booking" class="sm:max-w-lg">
      <DialogHeader>
        <DialogTitle>{{ t("reconcile.book") }}</DialogTitle>
        <DialogDescription>
          {{ t("reconcile.bookHint", { amount: formatAmount(booking.amount), date: formatDate(booking.line_date as string) }) }}
        </DialogDescription>
      </DialogHeader>
      <form id="book-form" class="space-y-3" @submit.prevent="confirmBook">
        <div class="space-y-1.5">
          <Label for="bk-account">{{ t(Number(booking.amount) > 0 ? "reconcile.incomeAccount" : "reconcile.expenseAccount") }}</Label>
          <SearchSelect id="bk-account" v-model="bookAccount" :options="accountOptions" required />
        </div>
        <div class="space-y-1.5">
          <Label for="bk-desc">{{ t("common.description") }}</Label>
          <input id="bk-desc" v-model="bookDescription" :class="FIELD_CLASS" />
        </div>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="booking = null">{{ t("common.cancel") }}</Button>
        <Button type="submit" form="book-form" class="active:scale-95" :disabled="book.isPending.value || !bookAccount" :loading="book.isPending.value">
          <BookPlus /> {{ t("reconcile.bookConfirm") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>

  <ConfirmDialog
    v-model:open="finishing"
    :title="t('reconcile.finishTitle')"
    :description="t('reconcile.finishBody')"
    :confirm-label="t('reconcile.finish')"
    :busy="finish.isPending.value"
    @confirm="run(() => finish.mutateAsync({ p_statement_id: statement.id }), t('reconcile.finishedOk')).then((ok) => ok && (finishing = false))"
  />
  <ConfirmDialog
    :open="!!deletingLine"
    :title="t('common.deleteTitle')"
    :description="t('common.deleteBody')"
    :confirm-label="t('common.delete')"
    :busy="removeLine.isPending.value"
    destructive
    @update:open="deletingLine = null"
    @confirm="run(() => removeLine.mutateAsync(deletingLine!.id), t('reconcile.deleted')).then((ok) => ok && (deletingLine = null))"
  />
</template>
