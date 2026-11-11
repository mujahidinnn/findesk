<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { useQueryClient } from "@tanstack/vue-query";
import { Divide, RefreshCw, Save, Trash2, X } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { spreadEvenly } from "@/components/budget/spread";
import { useAccountOptions } from "@/composables/useLookups";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatAmount } from "@/lib/format";

const props = defineProps<{ budget: MasterRow; editable: boolean }>();
const { t, locale } = useI18n();
const qc = useQueryClient();
const serverError = useServerError();

// ponytail: one page of 1000 lines (about 83 accounts × 12 months); page it if a budget ever grows past that.
const lines = useMasterRows("t_budget_lines", { filter: () => ({ budget_id: props.budget.id }) });
const accounts = useAccountOptions({ types: ["revenue", "expense"] });
const accountById = computed(() => new Map((accounts.rows.data.value ?? []).map((a) => [a.id, a])));

const start = computed(() => new Date(`${(props.budget.fiscal_year as { start_date?: string } | null)?.start_date ?? `${new Date().getFullYear()}-01-01`}T00:00`));
const months = computed(() =>
  Array.from({ length: 12 }, (_, i) => new Date(start.value.getFullYear(), start.value.getMonth() + i, 1).toLocaleDateString(locale.value, { month: "short" })),
);

interface Row { account_id: number; amounts: number[] }
const rows = ref<Row[]>([]);
const removed = ref<number[]>([]);
const dirty = ref(false);
function load(data: MasterRow[] | undefined) {
  const map = new Map<number, number[]>();
  for (const l of data ?? []) {
    const id = Number(l.account_id);
    if (!map.has(id)) map.set(id, Array(12).fill(0));
    map.get(id)![Number(l.period_no) - 1] = Number(l.amount);
  }
  rows.value = [...map].map(([account_id, amounts]) => ({ account_id, amounts }));
  removed.value = [];
  dirty.value = false;
}
watch(() => lines.data.value, (d) => !dirty.value && load(d), { immediate: true });

const sorted = computed(() =>
  [...rows.value].sort((a, b) => String(accountById.value.get(a.account_id)?.code ?? "").localeCompare(String(accountById.value.get(b.account_id)?.code ?? ""))),
);
const label = (id: number) => {
  const a = accountById.value.get(id);
  return a ? `${a.code} · ${a.name}` : String(id);
};
const typeOf = (id: number) => String(accountById.value.get(id)?.account_type ?? "");
const sum = (xs: number[]) => xs.reduce((s, x) => s + x, 0);
const columnTotals = computed(() =>
  ["revenue", "expense"]
    .map((type) => ({ type, amounts: months.value.map((_, i) => sum(rows.value.filter((r) => typeOf(r.account_id) === type).map((r) => r.amounts[i]))) }))
    .filter((c) => rows.value.some((r) => typeOf(r.account_id) === c.type)),
);

const freeAccounts = computed(() => accounts.options.value.filter((o) => !rows.value.some((r) => r.account_id === o.value)));
const adding = ref<number | null>(null);
function addAccount(id: number | null) {
  if (id == null) return;
  rows.value.push({ account_id: id, amounts: Array(12).fill(0) });
  removed.value = removed.value.filter((x) => x !== id);
  dirty.value = true;
  adding.value = null;
}
function removeRow(row: Row) {
  rows.value = rows.value.filter((r) => r !== row);
  removed.value.push(row.account_id);
  dirty.value = true;
}
function setCell(row: Row, i: number, v: number | null) {
  row.amounts[i] = v ?? 0;
  dirty.value = true;
}

const spreading = ref<Row | null>(null);
const annual = ref<number | null>(null);
function openSpread(row: Row) {
  spreading.value = row;
  annual.value = sum(row.amounts) || null;
}
function applySpread() {
  if (!spreading.value) return;
  spreading.value.amounts = spreadEvenly(annual.value ?? 0);
  dirty.value = true;
  spreading.value = null;
}

const saving = ref(false);
async function save() {
  saving.value = true;
  try {
    const id = props.budget.id;
    if (removed.value.length) {
      const { error } = await supabase.from("t_budget_lines").delete().eq("budget_id", id).in("account_id", removed.value);
      if (error) throw error;
    }
    const upserts = rows.value.flatMap((r) => r.amounts.map((amount, i) => ({ budget_id: id, account_id: r.account_id, period_no: i + 1, amount })));
    if (upserts.length) {
      const { error } = await supabase.from("t_budget_lines").upsert(upserts, { onConflict: "budget_id,account_id,period_no" });
      if (error) throw error;
    }
    dirty.value = false;
    await Promise.all([qc.invalidateQueries({ queryKey: ["t_budget_lines"] }), qc.invalidateQueries({ queryKey: ["budget_vs_actual"] })]);
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    saving.value = false;
  }
}
const CELL = "border-input bg-background focus-visible:ring-ring/50 h-8 w-24 rounded-md border px-2 text-right text-xs tabular-nums outline-none focus-visible:ring-3";
</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("budgets.tabs.editor") }}</h2>
      <template v-if="editable">
        <SearchSelect
          v-model="adding"
          :options="freeAccounts"
          :placeholder="t('budgets.addAccount')"
          class="w-full sm:w-64"
          :aria-label="t('budgets.addAccount')"
          @update:model-value="addAccount"
        />
        <Button v-if="dirty" variant="outline" size="sm" @click="load(lines.data.value)"><X /> {{ t("budgets.discard") }}</Button>
        <Button size="sm" class="active:scale-95" :disabled="!dirty || saving" :loading="saving" @click="save"><Save /> {{ t("common.save") }}</Button>
      </template>
    </div>
    <p v-if="!editable && budget.status === 'approved'" class="text-muted-foreground text-xs">{{ t("budgets.lockedHint") }}</p>

    <LoadingState v-if="lines.isPending.value || accounts.rows.isPending.value" :columns="8" />
    <EmptyState v-else-if="lines.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="lines.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!rows.length" :title="t('budgets.noLines')" :description="editable ? t('budgets.noLinesHint') : undefined" />
    <div v-else class="bg-card overflow-x-auto rounded-xl border">
      <table class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr>
            <th class="bg-muted sticky left-0 min-w-56 px-3 py-2 font-medium">{{ t("common.account") }}</th>
            <th v-for="m in months" :key="m" class="px-1 py-2 text-right font-medium">{{ m }}</th>
            <th class="px-3 py-2 text-right font-medium">{{ t("common.total") }}</th>
            <th v-if="editable" class="w-px px-2 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in sorted" :key="row.account_id" class="border-b last:border-0">
            <td class="bg-card sticky left-0 px-3 py-1.5">
              <span class="font-mono text-xs">{{ label(row.account_id) }}</span>
              <span class="text-muted-foreground block text-[11px]">{{ t(`budgets.types.${typeOf(row.account_id)}`) }}</span>
            </td>
            <td v-for="(m, i) in months" :key="m" class="px-1 py-1.5 text-right tabular-nums">
              <input
                v-if="editable"
                type="number"
                step="1"
                :value="row.amounts[i] || ''"
                placeholder="0"
                :class="CELL"
                :aria-label="`${label(row.account_id)} ${m}`"
                @change="setCell(row, i, ($event.target as HTMLInputElement).value === '' ? 0 : Number(($event.target as HTMLInputElement).value))"
              />
              <span v-else class="text-xs">{{ formatAmount(row.amounts[i]) }}</span>
            </td>
            <td class="px-3 py-1.5 text-right font-medium whitespace-nowrap tabular-nums">{{ formatAmount(sum(row.amounts)) }}</td>
            <td v-if="editable" class="px-2 py-1.5">
              <div class="flex justify-end gap-1">
                <Button variant="ghost" size="icon" class="size-8" :tooltip="t('budgets.spread')" @click="openSpread(row)"><Divide /></Button>
                <Button variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="removeRow(row)"><Trash2 /></Button>
              </div>
            </td>
          </tr>
        </tbody>
        <tfoot class="border-t border-dashed text-xs font-semibold">
          <tr v-for="c in columnTotals" :key="c.type">
            <td class="bg-card sticky left-0 px-3 py-2">{{ t("budgets.totalOf", { type: t(`budgets.types.${c.type}`) }) }}</td>
            <td v-for="(m, i) in months" :key="m" class="px-1 py-2 text-right tabular-nums">{{ formatAmount(c.amounts[i]) }}</td>
            <td class="px-3 py-2 text-right whitespace-nowrap tabular-nums">{{ formatAmount(sum(c.amounts)) }}</td>
            <td v-if="editable" />
          </tr>
        </tfoot>
      </table>
    </div>

    <Dialog :open="!!spreading" @update:open="(v) => !v && (spreading = null)">
      <DialogContent class="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>{{ t("budgets.spread") }}</DialogTitle>
          <DialogDescription>{{ spreading ? label(spreading.account_id) : "" }}</DialogDescription>
        </DialogHeader>
        <form id="spread-form" class="space-y-1.5" @submit.prevent="applySpread">
          <Label for="spread-annual">{{ t("budgets.annual") }}</Label>
          <MoneyInput id="spread-annual" v-model="annual" required />
          <p class="text-muted-foreground text-xs">{{ t("budgets.spreadHint") }}</p>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="spreading = null">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="spread-form"><Divide /> {{ t("budgets.spread") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </section>
</template>
