<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Banknote, Info, Pencil, Plus, Send, Trash2, User, UsersRound } from "@lucide/vue";
import ClaimDialog from "@/components/expense/ClaimDialog.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import TabBar from "@/components/common/TabBar.vue";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { useBankOptions } from "@/composables/useLookups";
import { useDeleteMasterRow, useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { useTabParam } from "@/composables/useTabParam";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { useAuthStore } from "@/stores/auth";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const TABS = computed(() => (can("expense-all", "read") ? (["mine", "all"] as const) : (["mine"] as const)));
const tab = useTabParam(() => TABS.value);
const tabs = computed(() =>
  TABS.value.map((key) => ({ key, label: t(`expenses.tabs.${key}`), icon: key === "mine" ? User : UsersRound })),
);

const claims = useMasterRows("t_expense_claims", {
  columns: "*, employee:profiles!employee_id(full_name)",
  filter: () => (tab.value === "all" ? undefined : { employee_id: auth.user?.id }),
  descending: true,
  enabled: () => !!auth.user,
});
const employee = (r: MasterRow) => (r.employee as { full_name?: string } | null)?.full_name ?? "";
const canEdit = (r: MasterRow) => r.status === "draft" && ((r.employee_id === auth.user?.id && can("expense", "create")) || can("expense", "update"));
const canPay = computed(() => can("cash-bank", "update"));

const submitClaim = useRpcMutation("submit_expense_claim", ["t_expense_claims", "pending_approvals"]);
const pay = useRpcMutation("pay_expense_claim", ["t_expense_claims", "t_journals"]);
const remove = useDeleteMasterRow("t_expense_claims");
const run = async (action: () => Promise<unknown>) => {
  try {
    await action();
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
};

const dialogOpen = ref(false);
const current = ref<MasterRow | null>(null);
function openClaim(row: MasterRow | null) {
  current.value = row;
  dialogOpen.value = true;
}
watch(dialogOpen, (v) => !v && route.query.id && router.replace({ query: { ...route.query, id: undefined } }));
watch(
  [() => route.query.id, () => claims.data.value],
  ([id]) => {
    const row = id ? claims.data.value?.find((r) => String(r.id) === id) : null;
    if (row && !dialogOpen.value) openClaim(row);
  },
  { immediate: true },
);

const deleting = ref<MasterRow | null>(null);
const paying = ref<MasterRow | null>(null);
const banks = useBankOptions("IDR");
const payForm = ref({ bank_id: null as number | null, date: isoDate() });
watch(paying, (r) => r && (payForm.value = { bank_id: banks.options.value[0]?.value ?? null, date: isoDate() }));
</script>

<template>
  <div class="space-y-4">
    <TabBar v-if="tabs.length > 1" v-model="tab" :tabs="tabs" />
    <DocTable
      :title="t(`expenses.tabs.${tab}`)"
      :columns="[t('expenses.docNo'), t('expenses.claimTitle'), ...(tab === 'all' ? [t('expenses.employee')] : []), t('common.date'), t('common.total'), t('common.status'), '']"
      :rows="claims.data.value ?? []"
      :pending="claims.isPending.value"
      :failed="claims.isError.value"
      :status-label="(s: string) => t(`status.${s}`)"
      @retry="claims.refetch()"
    >
      <template #toolbar>
        <Button v-if="can('expense', 'create')" size="sm" @click="openClaim(null)"><Plus /> {{ t("expenses.new") }}</Button>
      </template>
      <template #row="{ row }">
        <td class="font-mono text-xs whitespace-nowrap">{{ row.doc_no ?? `Draft #${row.id}` }}</td>
        <td>
          {{ row.title }}
          <span v-if="row.status === 'draft' && row.reject_reason" class="block text-xs text-rose-600">{{ t("expenses.rejected") }}: {{ row.reject_reason }}</span>
        </td>
        <td v-if="tab === 'all'">{{ employee(row) }}</td>
        <td class="whitespace-nowrap tabular-nums">{{ formatDate(row.claim_date as string) }}</td>
        <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(row.total) }}</td>
        <td><DocStatus :status="String(row.status)" /></td>
        <td>
          <div class="flex justify-end gap-1">
            <template v-if="canEdit(row)">
              <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openClaim(row)"><Pencil /></Button>
              <Button
                variant="soft"
                size="icon"
                class="size-8"
                :disabled="submitClaim.isPending.value || !Number(row.total)"
                :loading="submitClaim.isPending.value && submitClaim.variables.value?.p_id === row.id"
                :tooltip="t('common.submit')"
                @click="run(() => submitClaim.mutateAsync({ p_id: row.id }))"
              >
                <Send />
              </Button>
              <Button variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
            </template>
            <template v-else>
              <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="openClaim(row)"><Info /></Button>
              <Button v-if="row.status === 'approved' && canPay" variant="soft" size="icon" class="size-8" :tooltip="t('expenses.pay')" @click="paying = row">
                <Banknote />
              </Button>
            </template>
          </div>
        </td>
      </template>
    </DocTable>

    <ClaimDialog v-model:open="dialogOpen" :claim="current" />

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
      :open="!!paying"
      :title="t('expenses.pay')"
      :description="paying ? `${paying.doc_no} · ${employee(paying)} · ${formatMoney(paying.total)}` : ''"
      :confirm-label="t('expenses.pay')"
      :busy="pay.isPending.value || !payForm.bank_id"
      @update:open="paying = null"
      @confirm="run(async () => { await pay.mutateAsync({ p_id: paying!.id, p_bank_id: payForm.bank_id!, p_date: payForm.date }); paying = null; })"
    >
      <div class="space-y-3">
        <div class="space-y-1.5">
          <Label for="pay-bank">{{ t("expenses.paidFrom") }}</Label>
          <AppSelect id="pay-bank" v-model="payForm.bank_id" :options="banks.options.value" :placeholder="t('common.pick')" required />
        </div>
        <div class="space-y-1.5">
          <Label for="pay-date">{{ t("common.date") }}</Label>
          <input id="pay-date" v-model="payForm.date" type="date" :class="FIELD_CLASS" required />
        </div>
      </div>
    </ConfirmDialog>
  </div>
</template>
