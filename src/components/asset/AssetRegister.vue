<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Info, Pencil, PackageMinus, Plus, Power, Save, Trash2 } from "@lucide/vue";
import AssetDetailDialog from "@/components/asset/AssetDetailDialog.vue";
import AssetDisposeDialog from "@/components/asset/AssetDisposeDialog.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSimpleOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, useSaveMasterRow, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useQuery } from "@tanstack/vue-query";
import { supabase } from "@/integrations/supabase/client";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { costCenterName } from "@/lib/accountName";
import { FIELD_CLASS } from "@/lib/utils";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { can } = usePermissions();
const serverError = useServerError();

const assets = useMasterRows("t_assets", {
  columns: "*, category:m_asset_categories(code, name), cost_center:m_cost_centers(code, name)",
  descending: true,
});
const summary = useQuery({
  queryKey: ["asset_register_summary"],
  queryFn: async () => {
    const { data, error } = await supabase.rpc("asset_register_summary");
    if (error) throw error;
    return data;
  },
});
const categories = useMasterRows("m_asset_categories", { order: "code" });
const categoryOptions = computed(() =>
  (categories.data.value ?? []).filter((c) => c.is_active).map((c) => ({ value: c.id, label: `${c.code} · ${c.name}` })),
);
const costCenters = useSimpleOptions("m_cost_centers");

const accBy = computed(() => new Map((summary.data.value ?? []).map((s) => [Number(s.asset_id), Number(s.accumulated)])));
const accumulated = (r: MasterRow) => accBy.value.get(r.id) ?? Number(r.accumulated_opening);
const bookValue = (r: MasterRow) => Number(r.cost) - accumulated(r);
const name = (v: unknown) => (v as { name?: string } | null)?.name ?? "";
const ccLabel = (v: unknown) => { const c = v as { code?: string; name?: string } | null; return c?.name ? costCenterName(String(c.code), c.name) : ""; };

const totals = computed(() => {
  const live = (assets.data.value ?? []).filter((r) => r.status !== "disposed");
  const cost = live.reduce((s, r) => s + Number(r.cost), 0);
  const acc = live.reduce((s, r) => s + accumulated(r), 0);
  return [
    { label: t("assets.cost"), value: cost },
    { label: t("assets.accumulated"), value: acc },
    { label: t("assets.bookValue"), value: cost - acc },
  ];
});

const save = useSaveMasterRow("t_assets");
const remove = useDeleteMasterRow("t_assets");
const activate = useRpcMutation("activate_asset", ["t_assets"]);

const run = async (action: () => Promise<unknown>) => {
  try {
    await action();
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
};

interface AssetForm {
  code: string;
  name: string;
  category_id: number | null;
  acquisition_date: string;
  in_service_date: string;
  cost: number | null;
  salvage_value: number | null;
  method: string;
  useful_life_months: number | null;
  accumulated_opening: number | null;
  cost_center_id: number | null;
  location: string;
  serial_no: string;
  source_invoice_id: number | null;
  note: string;
}
const blank = (): AssetForm => ({
  code: "", name: "", category_id: null, acquisition_date: isoDate(), in_service_date: isoDate(), cost: null, salvage_value: 0,
  method: "straight_line", useful_life_months: 48, accumulated_opening: 0, cost_center_id: null, location: "", serial_no: "",
  source_invoice_id: null, note: "",
});
const formOpen = ref(false);
const editing = ref<MasterRow | null>(null);
const form = ref<AssetForm>(blank());
const METHODS = ["straight_line", "declining", "none"];

const bills = useMasterRows("t_invoices", {
  columns: "id, doc_no, invoice_date, total, partner:m_partners(name)",
  filter: () => ({ doc_type: "purchase_bill" }),
  descending: true,
  enabled: () => formOpen.value && can("payable", "read"),
});
const billOptions = computed(() =>
  (bills.data.value ?? []).filter((b) => b.doc_no).map((b) => ({ value: b.id, label: `${b.doc_no} · ${name(b.partner)} · ${formatMoney(b.total)}` })),
);

function openForm(row: MasterRow | null) {
  editing.value = row;
  const b = blank();
  form.value = row ? (Object.fromEntries(Object.entries(b).map(([k, v]) => [k, row[k] ?? v])) as unknown as AssetForm) : b;
  formOpen.value = true;
}
function pickCategory(id: number | null) {
  form.value.category_id = id;
  const c = categories.data.value?.find((x) => x.id === id);
  if (c) {
    form.value.method = String(c.method);
    form.value.useful_life_months = Number(c.useful_life_months);
  }
}
const submit = () =>
  run(async () => {
    const f = form.value;
    await save.mutateAsync({
      id: editing.value?.id,
      values: {
        ...f,
        code: f.code.trim().toUpperCase(),
        name: f.name.trim(),
        salvage_value: f.salvage_value ?? 0,
        accumulated_opening: f.accumulated_opening ?? 0,
        useful_life_months: f.method === "none" ? 0 : f.useful_life_months,
        location: f.location.trim() || null,
        serial_no: f.serial_no.trim() || null,
        note: f.note.trim() || null,
      },
    });
    formOpen.value = false;
  });

async function prefillFromLine(lineId: number) {
  const { data, error } = await supabase
    .from("t_invoice_lines")
    .select("description, line_subtotal, account_id, item:m_items(name), invoice:t_invoices(id, invoice_date)")
    .eq("id", lineId)
    .single();
  if (error) return void toast.error(serverError(error));
  const line = data as unknown as { description: string | null; line_subtotal: number; account_id: number | null; item: { name: string } | null; invoice: { id: number; invoice_date: string } };
  const cat = line.account_id
    ? (await supabase.from("m_asset_categories").select("id").eq("asset_account_id", line.account_id).eq("is_active", true).limit(1).maybeSingle()).data
    : null;
  openForm(null);
  form.value = {
    ...form.value, name: line.description ?? line.item?.name ?? "", cost: Number(line.line_subtotal),
    acquisition_date: line.invoice.invoice_date, in_service_date: line.invoice.invoice_date, source_invoice_id: line.invoice.id,
  };
  if (cat) pickCategory(cat.id);
  void router.replace({ query: { ...route.query, bill: undefined, line: undefined } });
}
if (route.query.line && can("asset", "create")) void prefillFromLine(Number(route.query.line));

const deleting = ref<MasterRow | null>(null);
const detail = ref<MasterRow | null>(null);
const disposing = ref<MasterRow | null>(null);
watch(
  [() => route.query.id, () => assets.data.value],
  ([id]) => {
    const row = id ? assets.data.value?.find((r) => String(r.id) === id) : null;
    if (row) detail.value = row;
  },
  { immediate: true },
);
</script>

<template>
  <div class="space-y-4">
    <div class="grid gap-3 sm:grid-cols-3">
      <div v-for="c in totals" :key="c.label" class="bg-card rounded-xl border p-4">
        <p class="text-muted-foreground text-xs">{{ c.label }}</p>
        <p class="mt-1 text-lg font-semibold tabular-nums">{{ formatMoney(c.value) }}</p>
      </div>
    </div>

    <DocTable
      :title="t('assets.register')"
      :columns="[t('common.code'), t('common.name'), t('assets.category'), t('assets.inService'), t('assets.cost'), t('assets.accumulated'), t('assets.bookValue'), t('common.status'), t('common.costCenter'), t('assets.location'), '']"
      :rows="assets.data.value ?? []"
      :pending="assets.isPending.value"
      :failed="assets.isError.value"
      :status-label="(s: string) => t(`status.${s}`)"
      @retry="assets.refetch()"
    >
      <template #toolbar>
        <Button v-if="can('asset', 'create')" size="sm" @click="openForm(null)"><Plus /> {{ t("assets.new") }}</Button>
      </template>
      <template #row="{ row }">
        <td class="font-mono text-xs">{{ row.code }}</td>
        <td>
          {{ row.name }}
          <span v-if="row.serial_no" class="text-muted-foreground block text-xs">{{ row.serial_no }}</span>
        </td>
        <td>{{ name(row.category) }}</td>
        <td class="whitespace-nowrap tabular-nums">{{ formatDate(row.in_service_date as string) }}</td>
        <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(row.cost) }}</td>
        <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(accumulated(row)) }}</td>
        <td class="text-right font-medium whitespace-nowrap tabular-nums">{{ row.status === "disposed" ? "-" : formatMoney(bookValue(row)) }}</td>
        <td><DocStatus :status="String(row.status)" /></td>
        <td>{{ ccLabel(row.cost_center) || "-" }}</td>
        <td>{{ row.location ?? "-" }}</td>
        <td>
          <div class="flex justify-end gap-1">
            <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="detail = row"><Info /></Button>
            <template v-if="row.status === 'draft'">
              <Button v-if="can('asset', 'update')" variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openForm(row)"><Pencil /></Button>
              <Button
                v-if="can('asset', 'update')"
                variant="soft"
                size="icon"
                class="size-8"
                :disabled="activate.isPending.value"
                :loading="activate.isPending.value && activate.variables.value?.p_id === row.id"
                :tooltip="t('assets.activate')"
                @click="run(() => activate.mutateAsync({ p_id: row.id }))"
              >
                <Power />
              </Button>
              <Button v-if="can('asset', 'delete')" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
            </template>
            <Button
              v-else-if="row.status === 'active' && can('asset', 'delete')"
              variant="ghost-destructive"
              size="icon"
              class="size-8"
              :tooltip="t('assets.dispose')"
              @click="disposing = row"
            >
              <PackageMinus />
            </Button>
          </div>
        </td>
      </template>
    </DocTable>

    <Dialog v-model:open="formOpen">
      <DialogContent class="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{{ editing ? t("assets.edit") : t("assets.new") }}</DialogTitle>
        </DialogHeader>
        <form id="asset-form" class="grid max-h-[70vh] gap-x-4 gap-y-3 overflow-y-auto p-1 sm:grid-cols-2" @submit.prevent="submit">
          <div class="space-y-1.5">
            <Label for="as-code">{{ t("common.code") }}</Label>
            <Input id="as-code" v-model="form.code" class="font-mono uppercase" placeholder="FA-0001" required />
          </div>
          <div class="space-y-1.5">
            <Label for="as-name">{{ t("common.name") }}</Label>
            <Input id="as-name" v-model="form.name" required />
          </div>
          <div class="space-y-1.5">
            <Label for="as-cat">{{ t("assets.category") }}</Label>
            <AppSelect id="as-cat" :model-value="form.category_id" :options="categoryOptions" :placeholder="t('common.pick')" required @update:model-value="pickCategory" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div class="space-y-1.5">
              <Label for="as-method">{{ t("assets.method") }}</Label>
              <AppSelect id="as-method" v-model="form.method" :options="METHODS.map((m) => ({ value: m, label: t(`assets.methods.${m}`) }))" required />
            </div>
            <div class="space-y-1.5">
              <Label for="as-life">{{ t("assets.lifeMonths") }}</Label>
              <input id="as-life" v-model.number="form.useful_life_months" type="number" min="0" step="1" :disabled="form.method === 'none'" :class="[FIELD_CLASS, 'text-right tabular-nums']" required />
            </div>
          </div>
          <div class="space-y-1.5">
            <Label for="as-acq">{{ t("assets.acquired") }}</Label>
            <input id="as-acq" v-model="form.acquisition_date" type="date" :class="FIELD_CLASS" required />
          </div>
          <div class="space-y-1.5">
            <Label for="as-svc">{{ t("assets.inService") }}</Label>
            <input id="as-svc" v-model="form.in_service_date" type="date" :min="form.acquisition_date" :class="FIELD_CLASS" required />
          </div>
          <div class="space-y-1.5">
            <Label for="as-cost">{{ t("assets.cost") }}</Label>
            <MoneyInput id="as-cost" v-model="form.cost" required />
          </div>
          <div class="space-y-1.5">
            <Label for="as-salvage">{{ t("assets.salvage") }}</Label>
            <MoneyInput id="as-salvage" v-model="form.salvage_value" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="as-opening">{{ t("assets.openingAccum") }}</Label>
            <MoneyInput id="as-opening" v-model="form.accumulated_opening" />
            <p class="text-muted-foreground text-xs">{{ t("assets.openingAccumHint") }}</p>
          </div>
          <div class="space-y-1.5">
            <Label for="as-cc">{{ t("common.costCenter") }}</Label>
            <AppSelect id="as-cc" v-model="form.cost_center_id" :options="costCenters.options.value" null-label="-" />
          </div>
          <div class="space-y-1.5">
            <Label for="as-loc">{{ t("assets.location") }}</Label>
            <Input id="as-loc" v-model="form.location" />
          </div>
          <div class="space-y-1.5">
            <Label for="as-serial">{{ t("assets.serial") }}</Label>
            <Input id="as-serial" v-model="form.serial_no" />
          </div>
          <div class="space-y-1.5">
            <Label for="as-bill">{{ t("assets.sourceBill") }}</Label>
            <SearchSelect id="as-bill" v-model="form.source_invoice_id" :options="billOptions" null-label="-" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="as-note">{{ t("common.note") }}</Label>
            <textarea id="as-note" v-model="form.note" :class="[FIELD_CLASS, 'h-16 py-2']" />
          </div>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="formOpen = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="asset-form" :disabled="save.isPending.value || !form.cost" :loading="save.isPending.value"><Save /> {{ t("common.save") }}</Button>
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
    <AssetDetailDialog v-model:asset="detail" :accumulated="detail ? accumulated(detail) : 0" />
    <AssetDisposeDialog v-model:asset="disposing" :book-value="disposing ? bookValue(disposing) : 0" />
  </div>
</template>
