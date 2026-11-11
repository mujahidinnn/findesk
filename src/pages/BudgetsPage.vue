<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ArrowLeft, ChartColumn, Grid3x3, Plus, Save, Pencil, Trash2, LockOpen, Check } from "@lucide/vue";
import BudgetEditor from "@/components/budget/BudgetEditor.vue";
import BudgetVsActual from "@/components/budget/BudgetVsActual.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCreateDocument } from "@/composables/useCreateDocument";
import { useSimpleOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, useSaveMasterRow, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { useTabParam } from "@/composables/useTabParam";
import { formatDate } from "@/lib/format";
import { costCenterName } from "@/lib/accountName";
import { FIELD_CLASS } from "@/lib/utils";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { can } = usePermissions();
const serverError = useServerError();

const budgets = useMasterRows("t_budgets", {
  columns: "*, fiscal_year:m_fiscal_years(year, start_date), cost_center:m_cost_centers(code, name)",
  descending: true,
});
const years = useMasterRows("m_fiscal_years", { order: "year", descending: true });
const costCenters = useSimpleOptions("m_cost_centers");
const selected = computed(() => budgets.data.value?.find((b) => String(b.id) === route.query.id) ?? null);
const openBudget = (id: number | null) => router.push({ query: id ? { id, tab: route.query.tab } : {} });
const year = (r: MasterRow) => (r.fiscal_year as { year?: number } | null)?.year;
const ccName = (r: MasterRow) => { const c = r.cost_center as { code?: string; name?: string } | null; return c?.name ? costCenterName(String(c.code), c.name) : undefined; };

const TABS = ["editor", "actual"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: "editor" as const, label: t("budgets.tabs.editor"), icon: Grid3x3 },
  { key: "actual" as const, label: t("budgets.tabs.actual"), icon: ChartColumn },
]);

const create = useCreateDocument("t_budgets", "t_budget_lines", "budget_id");
const save = useSaveMasterRow("t_budgets");
const remove = useDeleteMasterRow("t_budgets");
const approve = useRpcMutation("approve_budget", ["t_budgets", "budget_vs_actual"]);
const reopen = useRpcMutation("reopen_budget", ["t_budgets", "budget_vs_actual"]);

const run = async (action: () => Promise<unknown>) => {
  try {
    await action();
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
};

const formOpen = ref(false);
const editing = ref<MasterRow | null>(null);
const form = ref({ name: "", fiscal_year_id: null as number | null, cost_center_id: null as number | null, note: "" });
function openForm(row: MasterRow | null) {
  editing.value = row;
  form.value = row
    ? { name: String(row.name), fiscal_year_id: row.fiscal_year_id as number, cost_center_id: (row.cost_center_id as number | null) ?? null, note: String(row.note ?? "") }
    : { name: "", fiscal_year_id: years.data.value?.find((y) => y.status === "open")?.id ?? null, cost_center_id: null, note: "" };
  formOpen.value = true;
}
const submit = () =>
  run(async () => {
    const values = { name: form.value.name.trim(), cost_center_id: form.value.cost_center_id, note: form.value.note.trim() || null };
    if (editing.value) await save.mutateAsync({ id: editing.value.id, values });
    else openBudget(await create.mutateAsync({ header: { ...values, fiscal_year_id: form.value.fiscal_year_id }, lines: [] }));
    formOpen.value = false;
  });

const deleting = ref<MasterRow | null>(null);
const reopening = ref(false);
const canEdit = computed(() => selected.value?.status === "draft" && can("budget", "update"));
</script>

<template>
  <div class="space-y-4">
    <template v-if="selected">
      <div class="toolbar">
        <Button variant="ghost" size="icon" class="size-8" :tooltip="t('budgets.back')" @click="openBudget(null)"><ArrowLeft /></Button>
        <div class="mr-auto min-w-0">
          <h2 class="flex flex-wrap items-center gap-2 font-semibold">{{ selected.name }} <DocStatus :status="String(selected.status)" /></h2>
          <p class="text-muted-foreground text-xs">
            {{ t("budgets.fiscalYear") }} {{ year(selected) }} · {{ ccName(selected) ?? t("budgets.allCostCenters") }}
            <template v-if="selected.approved_at"> · {{ t("budgets.approvedAt", { date: formatDate(selected.approved_at as string) }) }}</template>
          </p>
        </div>
        <Button v-if="canEdit" variant="outline" size="sm" @click="openForm(selected)"><Pencil /> {{ t("common.edit") }}</Button>
        <template v-if="can('budget', 'delete')">
          <Button
            v-if="selected.status === 'draft'"
            size="sm"
            class="active:scale-95"
            :disabled="approve.isPending.value"
            :loading="approve.isPending.value"
            @click="run(() => approve.mutateAsync({ p_id: selected!.id }))"
          >
            <Check /> {{ t("common.approve") }}
          </Button>
          <Button v-else variant="outline" size="sm" @click="reopening = true"><LockOpen /> {{ t("budgets.reopen") }}</Button>
        </template>
      </div>
      <p v-if="selected.note" class="text-muted-foreground text-sm">{{ selected.note }}</p>
      <TabBar v-model="tab" :tabs="tabs" />
      <BudgetEditor v-if="tab === 'editor'" :key="selected.id" :budget="selected" :editable="canEdit" />
      <BudgetVsActual v-else :key="selected.id" :budget="selected" />
    </template>

    <DocTable
      v-else
      :title="t('budgets.list')"
      :columns="[t('common.name'), t('budgets.fiscalYear'), t('common.costCenter'), t('common.status'), '']"
      :rows="budgets.data.value ?? []"
      :pending="budgets.isPending.value"
      :failed="budgets.isError.value"
      :status-label="(s: string) => t(`status.${s}`)"
      @retry="budgets.refetch()"
    >
      <template #toolbar>
        <Button v-if="can('budget', 'create')" size="sm" @click="openForm(null)"><Plus /> {{ t("budgets.new") }}</Button>
      </template>
      <template #row="{ row }">
        <td>
          <button type="button" class="text-left font-medium hover:underline" @click="openBudget(row.id)">{{ row.name }}</button>
          <span v-if="row.note" class="text-muted-foreground block text-xs">{{ row.note }}</span>
        </td>
        <td class="tabular-nums">{{ year(row) }}</td>
        <td>{{ ccName(row) ?? t("budgets.allCostCenters") }}</td>
        <td><DocStatus :status="String(row.status)" /></td>
        <td>
          <div class="flex justify-end gap-1">
            <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="openBudget(row.id)"><Grid3x3 /></Button>
            <Button
              v-if="row.status === 'draft' && can('budget', 'delete')"
              variant="ghost-destructive"
              size="icon"
              class="size-8"
              :tooltip="t('common.delete')"
              @click="deleting = row"
            >
              <Trash2 />
            </Button>
          </div>
        </td>
      </template>
    </DocTable>

    <Dialog v-model:open="formOpen">
      <DialogContent class="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{{ editing ? t("budgets.edit") : t("budgets.new") }}</DialogTitle>
        </DialogHeader>
        <form id="budget-form" class="space-y-3" @submit.prevent="submit">
          <div class="space-y-1.5">
            <Label for="bg-name">{{ t("common.name") }}</Label>
            <Input id="bg-name" v-model="form.name" required />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="space-y-1.5">
              <Label for="bg-year">{{ t("budgets.fiscalYear") }}</Label>
              <AppSelect
                id="bg-year"
                v-model="form.fiscal_year_id"
                :options="(years.data.value ?? []).map((y) => ({ value: y.id, label: String(y.year) }))"
                :disabled="!!editing"
                :placeholder="t('common.pick')"
                required
              />
            </div>
            <div class="space-y-1.5">
              <Label for="bg-cc">{{ t("common.costCenter") }}</Label>
              <AppSelect id="bg-cc" v-model="form.cost_center_id" :options="costCenters.options.value" :null-label="t('budgets.allCostCenters')" />
            </div>
          </div>
          <div class="space-y-1.5">
            <Label for="bg-note">{{ t("common.note") }}</Label>
            <textarea id="bg-note" v-model="form.note" :class="[FIELD_CLASS, 'h-16 py-2']" />
          </div>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="formOpen = false">{{ t("common.cancel") }}</Button>
          <Button
            type="submit"
            form="budget-form"
            :disabled="create.isPending.value || save.isPending.value || !form.fiscal_year_id"
            :loading="create.isPending.value || save.isPending.value"
          >
            <Save /> {{ t("common.save") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <ConfirmDialog
      :open="!!deleting"
      :title="t('common.deleteTitle')"
      :description="t('common.deleteBody')"
      :confirm-label="t('common.delete')"
      :busy="remove.isPending.value"
      destructive
      @update:open="deleting = null"
      @confirm="run(async () => { await remove.mutateAsync(deleting!.id); deleting = null; })"
    />
    <ConfirmDialog
      v-model:open="reopening"
      :title="t('budgets.reopen')"
      :description="t('budgets.reopenBody')"
      :confirm-label="t('budgets.reopen')"
      :busy="reopen.isPending.value"
      @confirm="run(async () => { await reopen.mutateAsync({ p_id: selected!.id }); reopening = false; })"
    />
  </div>
</template>
