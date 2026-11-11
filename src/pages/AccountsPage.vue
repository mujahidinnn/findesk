<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { FolderKanban, ListTree, Pencil, Plus, RefreshCw, Save, Target } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import CrudTable, { type CrudField } from "@/components/common/CrudTable.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import TabBar from "@/components/common/TabBar.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCurrencyOptions, usePartnerOptions } from "@/composables/useLookups";
import { useMasterRows, useSaveMasterRow, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useServerError } from "@/composables/useServerError";
import { useTabParam } from "@/composables/useTabParam";
import { accountName } from "@/lib/accountName";
import { formatAmount, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const TABS = ["chart", "costCenters", "projects"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: "chart" as const, label: t("accounts.tabs.chart"), icon: ListTree },
  { key: "costCenters" as const, label: t("accounts.tabs.costCenters"), icon: Target },
  { key: "projects" as const, label: t("accounts.tabs.projects"), icon: FolderKanban },
]);

const SUBTYPES: Record<string, string[]> = {
  asset: ["cash", "bank", "receivable", "inventory", "prepaid", "tax_prepaid", "other_current_asset", "fixed_asset", "accumulated_depreciation", "other_asset"],
  liability: ["payable", "tax_payable", "accrued", "other_current_liability", "long_term_liability"],
  equity: ["equity", "retained_earnings"],
  revenue: ["revenue", "other_income"],
  expense: ["cogs", "expense", "depreciation", "other_expense", "tax_expense"],
};
const TYPES = Object.keys(SUBTYPES);
const typeOptions = computed(() => TYPES.map((v) => ({ value: v, label: t(`accounts.types.${v}`) })));

const accounts = useMasterRows("m_accounts", { order: "code" });
const showBalance = computed(() => can("reports", "read"));
const tb = useRpcQuery("trial_balance", () => (showBalance.value ? { p_from: "1900-01-01", p_to: isoDate() } : null));

const CREDIT_NORMAL = ["liability", "equity", "revenue"];
const balances = computed(() => {
  const own = new Map((tb.data.value ?? []).map((r) => [r.account_id, Number(r.closing)]));
  const kids = new Map<number | null, MasterRow[]>();
  for (const a of accounts.data.value ?? []) kids.set((a.parent_id as number | null) ?? null, [...(kids.get((a.parent_id as number | null) ?? null) ?? []), a]);
  const out = new Map<number, number>();
  const sum = (a: MasterRow): number => {
    const v = (CREDIT_NORMAL.includes(String(a.account_type)) ? -1 : 1) * (own.get(a.id) ?? 0) + (kids.get(a.id) ?? []).reduce((s, c) => s + sum(c), 0);
    out.set(a.id, v);
    return v;
  };
  (kids.get(null) ?? []).forEach(sum);
  return out;
});

const tree = computed(() => {
  const all = accounts.data.value ?? [];
  const ids = new Set(all.map((a) => a.id));
  const out: { row: MasterRow; depth: number }[] = [];
  const walk = (parent: number | null, depth: number) =>
    all
      .filter((a) => ((a.parent_id as number | null) ?? null) === parent || (parent === null && a.parent_id != null && !ids.has(a.parent_id as number)))
      .forEach((a) => {
        out.push({ row: a, depth });
        walk(a.id, depth + 1);
      });
  walk(null, 0);
  return out;
});
const search = ref("");
const typeFilter = ref<string | null>(null);
const visible = computed(() => {
  const q = search.value.trim().toLowerCase();
  return tree.value.filter(
    ({ row }) => (!typeFilter.value || row.account_type === typeFilter.value) && (!q || `${row.code} ${row.name}`.toLowerCase().includes(q)),
  );
});

const currencyOptions = useCurrencyOptions();
const save = useSaveMasterRow("m_accounts");
const formOpen = ref(false);
const editing = ref<MasterRow | null>(null);
const blank = () => ({
  code: "", name: "", parent_id: null as number | null, account_type: "asset", subtype: "other_current_asset",
  is_postable: true, is_control: false, currency: null as string | null, description: "", is_active: true,
});
const form = ref(blank());
const parentOptions = computed(() =>
  (accounts.data.value ?? [])
    .filter((a) => !a.is_postable && a.account_type === form.value.account_type && a.id !== editing.value?.id)
    .map((a) => ({ value: a.id, label: `${a.code} · ${accountName(String(a.code), String(a.name))}` })),
);
const subtypeOptions = computed(() => (SUBTYPES[form.value.account_type] ?? []).map((v) => ({ value: v, label: t(`accounts.subtypes.${v}`) })));
const controlAllowed = computed(() => ["receivable", "payable"].includes(form.value.subtype));
watch(() => form.value.account_type, (type) => {
  if (!SUBTYPES[type]?.includes(form.value.subtype)) form.value.subtype = SUBTYPES[type]![0]!;
  if (form.value.parent_id && !parentOptions.value.some((o) => o.value === form.value.parent_id)) form.value.parent_id = null;
});
watch(controlAllowed, (ok) => !ok && (form.value.is_control = false));

function openForm(row: MasterRow | null) {
  editing.value = row;
  form.value = row
    ? {
        code: String(row.code), name: String(row.name), parent_id: (row.parent_id as number | null) ?? null,
        account_type: String(row.account_type), subtype: String(row.subtype), is_postable: !!row.is_postable, is_control: !!row.is_control,
        currency: (row.currency as string | null) ?? null, description: (row.description as string | null) ?? "", is_active: !!row.is_active,
      }
    : blank();
  formOpen.value = true;
}
async function submit() {
  const f = form.value;
  try {
    await save.mutateAsync({
      id: editing.value?.id,
      values: { ...f, code: f.code.trim(), name: f.name.trim(), description: f.description.trim() || null },
    });
    formOpen.value = false;
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
}

const exportRows = () =>
  visible.value.map(({ row }) => ({
    [t("common.code")]: row.code,
    [t("common.name")]: row.name,
    [t("accounts.type")]: t(`accounts.types.${row.account_type}`),
    [t("accounts.subtype")]: t(`accounts.subtypes.${row.subtype}`),
    [t("accounts.postable")]: row.is_postable ? t("common.yes") : t("common.no"),
    [t("accounts.control")]: row.is_control ? t("common.yes") : t("common.no"),
    [t("common.currency")]: row.currency ?? "",
    [t("common.active")]: row.is_active ? t("common.yes") : t("common.no"),
    ...(showBalance.value && { [t("accounts.balance")]: balances.value.get(row.id) ?? 0 }),
  }));

const code: CrudField = { key: "code", label: t("common.code"), required: true, upper: true, mono: true };
const name: CrudField = { key: "name", label: t("common.name"), required: true };
const active: CrudField = { key: "is_active", label: t("common.active"), type: "boolean", default: true };
const costCenterFields = [code, name, active];
const { options: customers } = usePartnerOptions("customer");
const projectFields = computed<CrudField[]>(() => [
  code, name,
  { key: "partner_id", label: t("accounts.customer"), type: "select", options: customers.value },
  { key: "start_date", label: t("accounts.startDate"), type: "date" },
  { key: "end_date", label: t("accounts.endDate"), type: "date" },
  active,
]);
</script>

<template>
  <div class="space-y-6">
    <TabBar v-model="tab" :tabs="tabs" />

    <section v-if="tab === 'chart'" class="space-y-3">
      <div class="toolbar">
        <h2 class="mr-auto font-semibold">{{ t("accounts.title") }}</h2>
        <AppSelect v-model="typeFilter" :options="typeOptions" :null-label="t('accounts.allTypes')" class="w-40" :aria-label="t('accounts.type')" />
        <Input v-model="search" type="search" class="h-9 w-48" :placeholder="t('common.search')" :aria-label="t('common.search')" />
        <ExportMenu name="bagan-akun" :title="t('accounts.title')" :rows="exportRows" :disabled="!visible.length" />
        <Button v-if="can('account', 'create')" size="sm" @click="openForm(null)"><Plus /> {{ t("accounts.new") }}</Button>
      </div>

      <LoadingState v-if="accounts.isPending.value" :columns="7" :rows="12" />
      <EmptyState v-else-if="accounts.isError.value" :title="t('common.loadFailed')">
        <Button variant="outline" size="sm" @click="accounts.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
      </EmptyState>
      <EmptyState v-else-if="!visible.length" :title="t('common.empty')" />
      <div v-else class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr>
              <th class="px-3 py-2 font-medium">{{ t("common.account") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("accounts.type") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("accounts.subtype") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("accounts.flags") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("common.status") }}</th>
              <th v-if="showBalance" class="px-3 py-2 text-right font-medium">{{ t("accounts.balance") }}</th>
              <th class="w-px px-3 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="{ row, depth } in visible" :key="row.id" :class="['border-b last:border-0 [&>td]:px-3 [&>td]:py-2', !row.is_postable && 'bg-secondary/40 font-semibold']">
              <td>
                <div class="flex items-baseline gap-2" :style="{ paddingLeft: `${depth * 1.25}rem` }">
                  <span class="font-mono text-xs">{{ row.code }}</span>
                  <RouterLink v-if="row.is_postable" :to="`/ledger?account=${row.id}`" class="hover:text-primary-text hover:underline" :title="t('accounts.openLedger')">{{ accountName(String(row.code), String(row.name)) }}</RouterLink>
                  <span v-else>{{ accountName(String(row.code), String(row.name)) }}</span>
                  <span v-if="row.currency" class="text-muted-foreground text-xs">{{ row.currency }}</span>
                </div>
              </td>
              <td class="whitespace-nowrap">{{ t(`accounts.types.${row.account_type}`) }}</td>
              <td class="whitespace-nowrap">{{ t(`accounts.subtypes.${row.subtype}`) }}</td>
              <td>
                <div class="flex flex-wrap gap-1">
                  <StatusBadge v-if="!row.is_postable" tone="muted">{{ t("accounts.header") }}</StatusBadge>
                  <StatusBadge v-if="row.is_control" tone="info">{{ t("accounts.control") }}</StatusBadge>
                </div>
              </td>
              <td><StatusBadge :tone="row.is_active ? 'success' : 'muted'">{{ row.is_active ? t("common.active") : t("common.inactive") }}</StatusBadge></td>
              <td v-if="showBalance" class="text-right whitespace-nowrap tabular-nums">{{ tb.isPending.value ? "…" : formatAmount(balances.get(row.id)) }}</td>
              <td>
                <Button v-if="can('account', 'update')" variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openForm(row)"><Pencil /></Button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <CrudTable v-else-if="tab === 'costCenters'" table="m_cost_centers" feature="account" :title="t('accounts.costCenters')" :fields="costCenterFields" order="code" />
    <CrudTable v-else table="m_projects" feature="account" :title="t('accounts.projects')" :fields="projectFields" order="code" />

    <Dialog v-model:open="formOpen">
      <DialogContent class="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{{ editing ? t("accounts.edit") : t("accounts.new") }}</DialogTitle>
        </DialogHeader>
        <form id="account-form" class="grid max-h-[70vh] gap-x-4 gap-y-3 overflow-y-auto p-1 sm:grid-cols-2" @submit.prevent="submit">
          <div class="space-y-1.5">
            <Label for="acc-code">{{ t("common.code") }}</Label>
            <input id="acc-code" v-model="form.code" required pattern="[0-9A-Za-z.\-]+" :class="[FIELD_CLASS, 'font-mono']" />
          </div>
          <div class="space-y-1.5">
            <Label for="acc-name">{{ t("common.name") }}</Label>
            <input id="acc-name" v-model="form.name" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label for="acc-type">{{ t("accounts.type") }}</Label>
            <AppSelect id="acc-type" :model-value="form.account_type" :options="typeOptions" required @update:model-value="form.account_type = $event ?? 'asset'" />
          </div>
          <div class="space-y-1.5">
            <Label for="acc-subtype">{{ t("accounts.subtype") }}</Label>
            <AppSelect id="acc-subtype" :model-value="form.subtype" :options="subtypeOptions" required @update:model-value="form.subtype = $event ?? form.subtype" />
          </div>
          <div class="space-y-1.5">
            <Label for="acc-parent">{{ t("accounts.parent") }}</Label>
            <AppSelect id="acc-parent" v-model="form.parent_id" :options="parentOptions" :null-label="t('accounts.noParent')" />
          </div>
          <div class="space-y-1.5">
            <Label for="acc-currency">{{ t("common.currency") }}</Label>
            <AppSelect id="acc-currency" v-model="form.currency" :options="currencyOptions" :null-label="t('common.none')" />
            <p class="text-muted-foreground text-xs">{{ t("accounts.currencyHint") }}</p>
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="acc-desc">{{ t("common.description") }}</Label>
            <textarea id="acc-desc" v-model="form.description" :class="[FIELD_CLASS, 'h-16 py-2']" />
          </div>
          <div class="space-y-1 sm:col-span-2">
            <label class="flex items-center gap-2 text-sm"><input v-model="form.is_postable" type="checkbox" class="accent-primary size-4" /> {{ t("accounts.postable") }}</label>
            <p class="text-muted-foreground pl-6 text-xs">{{ t("accounts.postableHint") }}</p>
          </div>
          <div class="space-y-1 sm:col-span-2">
            <label :class="['flex items-center gap-2 text-sm', !controlAllowed && 'opacity-50']">
              <input v-model="form.is_control" type="checkbox" class="accent-primary size-4" :disabled="!controlAllowed" /> {{ t("accounts.control") }}
            </label>
            <p class="text-muted-foreground pl-6 text-xs">{{ t("accounts.controlHint") }}</p>
          </div>
          <label class="flex items-center gap-2 text-sm sm:col-span-2"><input v-model="form.is_active" type="checkbox" class="accent-primary size-4" /> {{ t("common.active") }}</label>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="formOpen = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="account-form" class="active:scale-95" :disabled="save.isPending.value" :loading="save.isPending.value"><Save /> {{ t("common.save") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
