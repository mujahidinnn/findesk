<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { useQueryClient } from "@tanstack/vue-query";
import { FileText, Paperclip, Plus, Save, Trash2, X } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { openReceipt } from "@/components/expense/receipt";
import { useCreateDocument } from "@/composables/useCreateDocument";
import { useAccountOptions, useSimpleOptions } from "@/composables/useLookups";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { useAuthStore } from "@/stores/auth";

const open = defineModel<boolean>("open", { required: true });
const props = defineProps<{ claim: MasterRow | null }>();
const { t } = useI18n();
const qc = useQueryClient();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const accounts = useAccountOptions({ types: ["expense"] });
const costCenters = useSimpleOptions("m_cost_centers");
const projects = useSimpleOptions("m_projects");
const accountLabel = (id: unknown) => accounts.options.value.find((o) => o.value === id)?.label ?? "";

const lines = useMasterRows("t_expense_claim_lines", {
  filter: () => ({ claim_id: props.claim?.id }),
  enabled: () => open.value && !!props.claim,
});

const editable = computed(
  () =>
    !props.claim ||
    (props.claim.status === "draft" && ((props.claim.employee_id === auth.user?.id && can("expense", "create")) || can("expense", "update"))),
);

interface Line {
  id?: number;
  expense_date: string;
  account_id: number | null;
  description: string;
  amount: number | null;
  cost_center_id: number | null;
  project_id: number | null;
  receipt_path: string | null;
}
const blankLine = (): Line => ({
  expense_date: isoDate(), account_id: null, description: "", amount: null, cost_center_id: null, project_id: null, receipt_path: null,
});
const header = ref({ title: "", claim_date: isoDate() });
const draft = ref<Line[]>([]);
const removedIds = ref<number[]>([]);

watch(
  [open, () => lines.data.value],
  ([o, data]) => {
    if (!o) return;
    header.value = { title: String(props.claim?.title ?? ""), claim_date: String(props.claim?.claim_date ?? isoDate()) };
    removedIds.value = [];
    if (!props.claim) draft.value = [blankLine()];
    else if (data)
      draft.value = data.map((l) => ({
        id: l.id,
        expense_date: String(l.expense_date),
        account_id: l.account_id as number,
        description: String(l.description),
        amount: Number(l.amount),
        cost_center_id: (l.cost_center_id as number | null) ?? null,
        project_id: (l.project_id as number | null) ?? null,
        receipt_path: (l.receipt_path as string | null) ?? null,
      }));
  },
  { immediate: true },
);
const total = computed(() => draft.value.reduce((s, l) => s + (l.amount ?? 0), 0));

function removeLine(i: number) {
  const [l] = draft.value.splice(i, 1);
  if (l.id) removedIds.value.push(l.id);
}

const uploading = ref<number | null>(null);
async function upload(line: Line, i: number, e: Event) {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  uploading.value = i;
  try {
    const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
    const path = `expense/${auth.user?.id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const { error } = await supabase.storage.from("attachments").upload(path, file, { contentType: file.type });
    if (error) throw error;
    line.receipt_path = path;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    uploading.value = null;
    input.value = "";
  }
}
const viewReceipt = async (path: string) => {
  try {
    await openReceipt(path);
  } catch (err) {
    toast.error(serverError(err));
  }
};

const create = useCreateDocument("t_expense_claims", "t_expense_claim_lines", "claim_id");
const saving = ref(false);
const lineValues = (l: Line) => ({
  expense_date: l.expense_date,
  account_id: l.account_id,
  description: l.description.trim(),
  amount: l.amount,
  cost_center_id: l.cost_center_id,
  project_id: l.project_id,
  receipt_path: l.receipt_path,
});
async function save() {
  saving.value = true;
  try {
    const head = { title: header.value.title.trim(), claim_date: header.value.claim_date };
    if (!props.claim) {
      await create.mutateAsync({ header: head, lines: draft.value.map(lineValues) });
    } else {
      const id = props.claim.id;
      const steps = [
        supabase.from("t_expense_claims").update(head).eq("id", id),
        ...(removedIds.value.length ? [supabase.from("t_expense_claim_lines").delete().in("id", removedIds.value)] : []),
      ];
      for (const s of steps) {
        const { error } = await s;
        if (error) throw error;
      }
      for (const l of draft.value) {
        const { error } = l.id
          ? await supabase.from("t_expense_claim_lines").update(lineValues(l) as never).eq("id", l.id)
          : await supabase.from("t_expense_claim_lines").insert({ ...lineValues(l), claim_id: id } as never);
        if (error) throw error;
      }
      await Promise.all(["t_expense_claims", "t_expense_claim_lines"].map((k) => qc.invalidateQueries({ queryKey: [k] })));
    }
    toast.success(t("common.saved"));
    open.value = false;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle class="flex flex-wrap items-center gap-2">
          {{ claim ? (claim.doc_no ?? `Draft #${claim.id}`) : t("expenses.new") }}
          <DocStatus v-if="claim" :status="String(claim.status)" />
        </DialogTitle>
      </DialogHeader>
      <div class="max-h-[72vh] space-y-4 overflow-y-auto p-1">
        <p v-if="claim?.status === 'draft' && claim.reject_reason" class="rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-300">
          {{ t("expenses.rejected") }}: {{ claim.reject_reason }}
        </p>
        <form v-if="editable" id="claim-form" class="space-y-4" @submit.prevent="save">
          <div class="grid gap-3 sm:grid-cols-[1fr_12rem]">
            <div class="space-y-1.5">
              <Label for="cl-title">{{ t("expenses.claimTitle") }}</Label>
              <Input id="cl-title" v-model="header.title" :placeholder="t('expenses.titlePlaceholder')" required />
            </div>
            <div class="space-y-1.5">
              <Label for="cl-date">{{ t("common.date") }}</Label>
              <input id="cl-date" v-model="header.claim_date" type="date" :class="FIELD_CLASS" required />
            </div>
          </div>
          <LoadingState v-if="claim && lines.isPending.value" variant="form" />
          <div v-else class="space-y-2">
            <div v-for="(l, i) in draft" :key="l.id ?? `new-${i}`" class="grid gap-2 rounded-lg border p-3 sm:grid-cols-6">
              <div class="space-y-1">
                <Label :for="`cl-l${i}-date`" class="text-xs">{{ t("common.date") }}</Label>
                <input :id="`cl-l${i}-date`" v-model="l.expense_date" type="date" :class="FIELD_CLASS" required />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <Label :for="`cl-l${i}-acc`" class="text-xs">{{ t("common.account") }}</Label>
                <SearchSelect :id="`cl-l${i}-acc`" v-model="l.account_id" :options="accounts.options.value" required />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <Label :for="`cl-l${i}-desc`" class="text-xs">{{ t("common.description") }}</Label>
                <Input :id="`cl-l${i}-desc`" v-model="l.description" required />
              </div>
              <div class="space-y-1">
                <Label :for="`cl-l${i}-amt`" class="text-xs">{{ t("common.amount") }}</Label>
                <MoneyInput :id="`cl-l${i}-amt`" v-model="l.amount" required />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <Label :for="`cl-l${i}-cc`" class="text-xs">{{ t("common.costCenter") }}</Label>
                <AppSelect :id="`cl-l${i}-cc`" v-model="l.cost_center_id" :options="costCenters.options.value" null-label="-" />
              </div>
              <div class="space-y-1 sm:col-span-2">
                <Label :for="`cl-l${i}-prj`" class="text-xs">{{ t("common.project") }}</Label>
                <AppSelect :id="`cl-l${i}-prj`" v-model="l.project_id" :options="projects.options.value" null-label="-" />
              </div>
              <div class="flex items-end gap-1 sm:col-span-2">
                <template v-if="l.receipt_path">
                  <Button type="button" variant="soft" size="sm" @click="viewReceipt(l.receipt_path)"><FileText /> {{ t("expenses.receipt") }}</Button>
                  <Button type="button" variant="ghost" size="icon" class="size-8" :tooltip="t('expenses.removeReceipt')" @click="l.receipt_path = null"><X /></Button>
                </template>
                <label v-else class="border-input hover:bg-accent inline-flex h-8 cursor-pointer items-center gap-1.5 rounded-md border px-3 text-sm">
                  <Paperclip class="size-4" /> {{ uploading === i ? t("common.loading") : t("expenses.attach") }}
                  <input type="file" accept="image/png,image/jpeg,image/webp,application/pdf" class="sr-only" :disabled="uploading != null" @change="upload(l, i, $event)" />
                </label>
                <Button
                  v-if="draft.length > 1"
                  type="button"
                  variant="ghost-destructive"
                  size="icon"
                  class="ml-auto size-8"
                  :tooltip="t('common.delete')"
                  @click="removeLine(i)"
                >
                  <Trash2 />
                </Button>
              </div>
            </div>
            <div class="flex items-center justify-between">
              <Button type="button" variant="outline" size="sm" @click="draft.push(blankLine())"><Plus /> {{ t("common.addLine") }}</Button>
              <span class="text-sm">{{ t("common.total") }}: <b class="tabular-nums">{{ formatMoney(total) }}</b></span>
            </div>
          </div>
        </form>

        <template v-else-if="claim">
          <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4">
            <div><dt class="text-muted-foreground text-xs">{{ t("expenses.claimTitle") }}</dt><dd>{{ claim.title }}</dd></div>
            <div><dt class="text-muted-foreground text-xs">{{ t("expenses.employee") }}</dt><dd>{{ (claim.employee as { full_name?: string } | null)?.full_name }}</dd></div>
            <div><dt class="text-muted-foreground text-xs">{{ t("common.date") }}</dt><dd>{{ formatDate(claim.claim_date as string) }}</dd></div>
            <div><dt class="text-muted-foreground text-xs">{{ t("common.total") }}</dt><dd class="font-medium tabular-nums">{{ formatMoney(claim.total) }}</dd></div>
            <div v-if="claim.paid_at"><dt class="text-muted-foreground text-xs">{{ t("expenses.paidAt") }}</dt><dd>{{ formatDate(claim.paid_at as string) }}</dd></div>
          </dl>
          <div v-if="can('journal', 'read') && (claim.journal_id || claim.payment_journal_id)" class="flex flex-wrap gap-3 text-sm">
            <RouterLink v-if="claim.journal_id" :to="`/journals?id=${claim.journal_id}`" class="text-primary-text hover:underline">{{ t("expenses.expenseJournal") }}</RouterLink>
            <RouterLink v-if="claim.payment_journal_id" :to="`/journals?id=${claim.payment_journal_id}`" class="text-primary-text hover:underline">{{ t("expenses.paymentJournal") }}</RouterLink>
          </div>
          <LoadingState v-if="lines.isPending.value" />
          <div v-else class="overflow-x-auto rounded-lg border">
            <table v-stack class="w-full text-sm">
              <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
                <tr>
                  <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
                  <th class="px-3 py-2 font-medium">{{ t("common.account") }}</th>
                  <th class="px-3 py-2 font-medium">{{ t("common.description") }}</th>
                  <th class="px-3 py-2 text-right font-medium">{{ t("common.amount") }}</th>
                  <th class="px-3 py-2 font-medium">{{ t("expenses.receipt") }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="l in draft" :key="l.id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                  <td class="whitespace-nowrap">{{ formatDate(l.expense_date) }}</td>
                  <td>{{ accountLabel(l.account_id) }}</td>
                  <td>{{ l.description }}</td>
                  <td class="text-right tabular-nums">{{ formatMoney(l.amount) }}</td>
                  <td>
                    <Button v-if="l.receipt_path" variant="ghost" size="icon" class="size-8" :tooltip="t('expenses.receipt')" @click="viewReceipt(l.receipt_path)"><FileText /></Button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ editable ? t("common.cancel") : t("common.close") }}</Button>
        <Button v-if="editable" type="submit" form="claim-form" :disabled="saving || !draft.length || uploading != null" :loading="saving"><Save /> {{ t("expenses.saveDraft") }}</Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
