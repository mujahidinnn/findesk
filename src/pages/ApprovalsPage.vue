<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Check, ExternalLink, Info, RefreshCw, X } from "@lucide/vue";
import ApprovalLines from "@/components/approval/ApprovalLines.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import ReasonDialog from "@/components/common/ReasonDialog.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useServerError } from "@/composables/useServerError";
import type { Database } from "@/integrations/supabase/types";
import { formatDate, formatMoney } from "@/lib/format";
import { useAuthStore } from "@/stores/auth";

type Pending = Database["public"]["Functions"]["pending_approvals"]["Returns"][number];

const { t } = useI18n();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const pending = useRpcQuery("pending_approvals", {} as never);
const groups = computed(() => {
  const map = new Map<string, Pending[]>();
  for (const r of pending.data.value ?? []) map.set(r.kind, [...(map.get(r.kind) ?? []), r]);
  return [...map].map(([kind, rows]) => ({ kind, rows }));
});
const kindLabel = (kind: string) => {
  const [base, docType] = kind.split(":");
  return docType ? t(`journalKinds.${docType}`) : t(`approvals.kinds.${base}`);
};
const LINKS: Record<string, string> = {
  journal: "/journals", "invoice:sales_invoice": "/sales/invoices", "invoice:sales_credit": "/sales/invoices",
  "invoice:purchase_bill": "/purchases/bills", "invoice:purchase_debit": "/purchases/bills", payment: "/purchases/payments",
  cash: "/cash", expense: "/expenses",
};
const linkOf = (r: Pending) => `${LINKS[r.kind] ?? "/"}?id=${r.id}`;
const isMine = (r: Pending) => r.requested_by_id === auth.user?.id;
const canDecide = computed(() => can("approval", "update"));

const decide = useRpcMutation("decide_document", [
  "pending_approvals", "t_journals", "t_invoices", "t_payments", "t_cash_txns", "t_expense_claims", "notifications",
]);
const viewing = ref<Pending | null>(null);
const rejecting = ref<Pending | null>(null);
const busyId = computed(() => (decide.isPending.value ? decide.variables.value?.p_id : null));

async function approve(r: Pending) {
  try {
    await decide.mutateAsync({ p_kind: r.kind, p_id: r.id, p_approve: true });
    toast.success(t("approvals.approved"));
    viewing.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}
async function reject(reason: string) {
  const r = rejecting.value;
  if (!r) return;
  try {
    await decide.mutateAsync({ p_kind: r.kind, p_id: r.id, p_approve: false, p_reason: reason });
    toast.success(t("approvals.rejected"));
    rejecting.value = null;
    viewing.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}
const amount = (r: Pending) => formatMoney(r.amount, r.currency);
</script>

<template>
  <div class="space-y-4">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">
        {{ t("approvals.inbox") }}
        <span v-if="pending.data.value?.length" class="text-muted-foreground ml-1 text-sm font-normal">({{ pending.data.value.length }})</span>
      </h2>
      <span v-for="g in groups" :key="g.kind" class="bg-primary-soft text-primary-text rounded-full px-2.5 py-1 text-xs font-medium">
        {{ kindLabel(g.kind) }} · {{ g.rows.length }}
      </span>
      <Button variant="outline" size="sm" :disabled="pending.isFetching.value" @click="pending.refetch()"><RefreshCw /> {{ t("approvals.refresh") }}</Button>
    </div>

    <LoadingState v-if="pending.isPending.value" />
    <EmptyState v-else-if="pending.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="pending.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!groups.length" :icon="Check" :title="t('approvals.allClear')" :description="t('approvals.allClearHint')" />

    <section v-for="g in groups" :key="g.kind" class="space-y-2">
      <h3 class="text-sm font-semibold">{{ kindLabel(g.kind) }} <span class="text-muted-foreground font-normal">· {{ g.rows.length }}</span></h3>
      <div class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full table-fixed sm:min-w-[56rem] text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr>
              <th class="w-40 px-3 py-2 font-medium">{{ t("approvals.document") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("common.description") }}</th>
              <th class="w-48 px-3 py-2 font-medium">{{ t("common.partner") }}</th>
              <th class="w-36 px-3 py-2 text-right font-medium">{{ t("common.amount") }}</th>
              <th class="w-40 px-3 py-2 font-medium">{{ t("approvals.requestedBy") }}</th>
              <th class="w-40 px-3 py-2 font-medium">{{ t("approvals.submittedAt") }}</th>
              <th class="w-32 px-3 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in g.rows" :key="r.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
              <td class="font-mono text-xs whitespace-nowrap">{{ r.doc_no ?? `Draft #${r.id}` }}</td>
              <td>{{ r.title ?? "-" }}</td>
              <td>{{ r.kind === "expense" ? "-" : (r.partner ?? "-") }}</td>
              <td class="text-right whitespace-nowrap tabular-nums">
                {{ amount(r) }}
                <span v-if="r.currency !== 'IDR'" class="text-muted-foreground block text-xs">{{ formatMoney(r.base_amount) }}</span>
              </td>
              <td>
                {{ r.requested_by ?? "-" }}
                <span v-if="isMine(r)" class="text-muted-foreground block text-xs">{{ t("approvals.yours") }}</span>
              </td>
              <td class="whitespace-nowrap">{{ formatDate(r.submitted_at, true) }}</td>
              <td>
                <div class="flex justify-end gap-1">
                  <Button variant="ghost" size="icon" class="size-8" :tooltip="t('approvals.view')" @click="viewing = r"><Info /></Button>
                  <template v-if="canDecide && !isMine(r)">
                    <Button
                      variant="soft"
                      size="icon"
                      class="size-8"
                      :disabled="decide.isPending.value"
                      :loading="busyId === r.id && decide.variables.value?.p_approve"
                      :tooltip="t('common.approve')"
                      @click="approve(r)"
                    >
                      <Check />
                    </Button>
                    <Button variant="ghost-destructive" size="icon" class="size-8" :disabled="decide.isPending.value" :tooltip="t('common.reject')" @click="rejecting = r">
                      <X />
                    </Button>
                  </template>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <Dialog :open="!!viewing" @update:open="(v) => !v && (viewing = null)">
      <DialogContent class="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle class="flex flex-wrap items-center gap-2">
            {{ kindLabel(viewing?.kind ?? "") }} <span class="font-mono text-sm">{{ viewing?.doc_no ?? `Draft #${viewing?.id}` }}</span>
          </DialogTitle>
          <DialogDescription>
            {{ [viewing?.title, viewing?.kind === "expense" ? null : viewing?.partner, viewing?.requested_by].filter(Boolean).join(" · ") }}
          </DialogDescription>
        </DialogHeader>
        <div v-if="viewing" class="max-h-[65vh] space-y-3 overflow-y-auto p-1">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <p class="text-lg font-semibold tabular-nums">{{ amount(viewing) }}</p>
            <RouterLink :to="linkOf(viewing)" class="text-primary-text inline-flex items-center gap-1 text-sm hover:underline">
              <ExternalLink class="size-3.5" /> {{ t("approvals.openDoc") }}
            </RouterLink>
          </div>
          <ApprovalLines :id="viewing.id" :key="`${viewing.kind}-${viewing.id}`" :kind="viewing.kind" />
          <p v-if="canDecide && isMine(viewing)" class="text-muted-foreground text-xs">{{ t("approvals.selfHint") }}</p>
        </div>
        <DialogFooter v-if="viewing && canDecide && !isMine(viewing)">
          <Button variant="outline" class="text-rose-600" :disabled="decide.isPending.value" @click="rejecting = viewing"><X /> {{ t("common.reject") }}</Button>
          <Button class="active:scale-95" :disabled="decide.isPending.value" :loading="decide.isPending.value" @click="approve(viewing)"><Check /> {{ t("common.approve") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <ReasonDialog
      :open="!!rejecting"
      :title="t('approvals.rejectTitle')"
      :description="rejecting ? `${kindLabel(rejecting.kind)} ${rejecting.doc_no ?? ''}` : ''"
      :confirm-label="t('common.reject')"
      :busy="decide.isPending.value"
      destructive
      @update:open="(v) => !v && (rejecting = null)"
      @confirm="reject"
    />
  </div>
</template>
