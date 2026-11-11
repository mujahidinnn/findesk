<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ExternalLink, RefreshCw, Undo2 } from "@lucide/vue";
import { useQuery } from "@tanstack/vue-query";
import type { SupabaseClient } from "@supabase/supabase-js";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { accountName } from "@/lib/accountName";
import { formatDate, formatMoney } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

type Ref = { code?: string; name?: string; full_name?: string } | null;
interface Line {
  id: number; line_no: number; debit: number; credit: number; memo: string | null; currency: string | null; fc_amount: number | null;
  account: Ref; partner: Ref; cost_center: Ref; project: Ref;
}
interface Journal {
  id: number; doc_no: string | null; journal_date: string; kind: string; status: string; memo: string | null; reference: string | null;
  source_type: string | null; source_id: number | null; reversal_of: number | null; reversed_by: number | null; reject_reason: string | null;
  posted_at: string | null; creator: Ref; lines: Line[];
}

const id = defineModel<number | null>("id", { required: true });
const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();
const db = supabase as unknown as SupabaseClient;

async function sourceLink(j: Journal) {
  if (j.source_type === "invoice") {
    const { data } = await supabase.from("t_invoices").select("doc_type").eq("id", j.source_id!).maybeSingle();
    return data ? `${data.doc_type.startsWith("sales") ? "/sales/invoices" : "/purchases/bills"}?id=${j.source_id}` : null;
  }
  if (j.source_type === "payment") {
    const { data } = await supabase.from("t_payments").select("direction").eq("id", j.source_id!).maybeSingle();
    return data ? `${data.direction === "in" ? "/sales/receipts" : "/purchases/payments"}?id=${j.source_id}` : null;
  }
  const id = j.source_id;
  switch (j.source_type) {
    case "cash_txn": return `/cash?id=${id}`;
    case "transfer": return "/cash?tab=transfers";
    case "expense_claim": return `/expenses?id=${id}`;
    case "asset": return `/assets?id=${id}`;
    case "depreciation": return "/assets?tab=depreciation";
    case "vat": return "/tax?tab=vat";
    default: return null;
  }
}

const journal = useQuery({
  queryKey: computed(() => ["t_journals", "detail", id.value]),
  enabled: computed(() => id.value != null),
  queryFn: async () => {
    const { data, error } = await db
      .from("t_journals")
      .select(
        "*, creator:profiles!t_journals_created_by_fkey(full_name), lines:t_journal_lines(*, account:m_accounts(code, name), partner:m_partners(name), cost_center:m_cost_centers(code, name), project:m_projects(code, name))",
      )
      .eq("id", id.value!)
      .single();
    if (error) throw error;
    const j = data as Journal;
    j.lines.sort((a, b) => a.line_no - b.line_no || a.id - b.id);
    return { ...j, link: await sourceLink(j) };
  },
});
const j = computed(() => journal.data.value);
const totals = computed(() => ({
  debit: (j.value?.lines ?? []).reduce((s, l) => s + Number(l.debit), 0),
  credit: (j.value?.lines ?? []).reduce((s, l) => s + Number(l.credit), 0),
}));
const canReverse = computed(
  () => j.value?.status === "posted" && ["manual", "opening", "recurring"].includes(j.value.kind) && can("journal", "delete"),
);

const reverse = useRpcMutation("reverse_journal", ["t_journals", "general_ledger", "trial_balance"]);
const reversing = ref(false);
const reverseDate = ref("");
const reverseReason = ref("");
function startReverse() {
  reverseDate.value = "";
  reverseReason.value = "";
  reversing.value = true;
}
async function confirmReverse() {
  try {
    const newId = await reverse.mutateAsync({ p_id: id.value!, p_date: reverseDate.value || undefined, p_reason: reverseReason.value.trim() });
    reversing.value = false;
    toast.success(t("journals.reversedToast"));
    id.value = newId;
  } catch (err) {
    toast.error(serverError(err));
  }
}

const open = computed({ get: () => id.value != null, set: (v) => !v && (id.value = null) });
const num = "text-right tabular-nums whitespace-nowrap";
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle class="flex flex-wrap items-center gap-2">
          {{ t("journals.detail") }}
          <span v-if="j" class="font-mono text-sm">{{ j.doc_no ?? t("journals.draftNo", { id: j.id }) }}</span>
          <DocStatus v-if="j" :status="j.status" />
        </DialogTitle>
      </DialogHeader>
      <LoadingState v-if="journal.isPending.value" variant="detail" />
      <EmptyState v-else-if="journal.isError.value || !j" :title="t('common.loadFailed')">
        <Button variant="outline" size="sm" @click="journal.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
      </EmptyState>
      <div v-else class="max-h-[75vh] space-y-4 overflow-y-auto">
        <p v-if="j.status === 'draft' && j.reject_reason" class="rounded-lg bg-rose-500/10 px-3 py-2 text-sm text-rose-700 dark:text-rose-400">
          {{ t("journals.rejected", { reason: j.reject_reason }) }}
        </p>
        <dl class="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
          <div><dt class="text-muted-foreground text-xs">{{ t("common.date") }}</dt><dd>{{ formatDate(j.journal_date) }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("journals.kind") }}</dt><dd>{{ t(`journalKinds.${j.kind}`) }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("common.reference") }}</dt><dd>{{ j.reference || "-" }}</dd></div>
          <div class="sm:col-span-3"><dt class="text-muted-foreground text-xs">{{ t("journals.memo") }}</dt><dd>{{ j.memo || "-" }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("common.createdBy") }}</dt><dd>{{ j.creator?.full_name ?? "-" }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("journals.postedAt") }}</dt><dd>{{ formatDate(j.posted_at, true) || "-" }}</dd></div>
        </dl>

        <div class="flex flex-wrap gap-2">
          <Button v-if="j.link" as-child variant="outline" size="sm">
            <RouterLink :to="j.link"><ExternalLink /> {{ t("journals.openSource") }}</RouterLink>
          </Button>
          <Button v-if="j.reversal_of" variant="outline" size="sm" @click="id = j.reversal_of"><ExternalLink /> {{ t("journals.reversalOf") }}</Button>
          <Button v-if="j.reversed_by" variant="outline" size="sm" @click="id = j.reversed_by"><ExternalLink /> {{ t("journals.reversedBy") }}</Button>
          <Button v-if="canReverse" variant="ghost-destructive" size="sm" class="ml-auto" @click="startReverse"><Undo2 /> {{ t("journals.reverse") }}</Button>
        </div>

        <div class="overflow-x-auto rounded-lg border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="px-3 py-2 font-medium">{{ t("common.account") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("journals.memo") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.partner") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.costCenter") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.debit") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("common.credit") }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="l in j.lines" :key="l.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                <td><span class="font-mono text-xs">{{ l.account?.code }}</span> {{ l.account ? accountName(String(l.account.code), String(l.account.name)) : "" }}</td>
                <td>
                  {{ l.memo || "-" }}
                  <span v-if="l.currency && l.fc_amount" class="text-muted-foreground block text-xs tabular-nums">{{ formatMoney(l.fc_amount, l.currency) }}</span>
                </td>
                <td>{{ l.partner?.name ?? "-" }}</td>
                <td>{{ [l.cost_center?.code, l.project?.code].filter(Boolean).join(" · ") || "-" }}</td>
                <td :class="num">{{ Number(l.debit) ? formatMoney(l.debit) : "-" }}</td>
                <td :class="num">{{ Number(l.credit) ? formatMoney(l.credit) : "-" }}</td>
              </tr>
            </tbody>
            <tfoot class="border-t font-semibold">
              <tr class="[&>td]:px-3 [&>td]:py-2">
                <td colspan="4">{{ t("common.total") }}</td>
                <td :class="num">{{ formatMoney(totals.debit) }}</td>
                <td :class="num">{{ formatMoney(totals.credit) }}</td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </DialogContent>
  </Dialog>

  <ConfirmDialog
    v-model:open="reversing"
    :title="t('journals.reverseTitle')"
    :description="t('journals.reverseBody')"
    :confirm-label="t('journals.reverse')"
    :busy="reverse.isPending.value || !reverseReason.trim()"
    destructive
    @confirm="confirmReverse"
  >
    <div class="space-y-3">
      <div class="space-y-1.5">
        <Label for="rev-date">{{ t("journals.reverseDate") }}</Label>
        <input id="rev-date" v-model="reverseDate" type="date" :min="j?.journal_date" :class="FIELD_CLASS" />
        <p class="text-muted-foreground text-xs">{{ t("journals.reverseDateHint") }}</p>
      </div>
      <div class="space-y-1.5">
        <Label for="rev-reason">{{ t("common.reason") }}</Label>
        <textarea id="rev-reason" v-model="reverseReason" rows="3" required :class="[FIELD_CLASS, 'h-auto py-2']" />
      </div>
    </div>
  </ConfirmDialog>
</template>
