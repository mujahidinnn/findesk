<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { BookOpen, Info, Pencil, Plus, Repeat, Send, Trash2 } from "@lucide/vue";
import { useQuery } from "@tanstack/vue-query";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import DocTable from "@/components/common/DocTable.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import TabBar from "@/components/common/TabBar.vue";
import JournalDetail from "@/components/journal/JournalDetail.vue";
import JournalEditor from "@/components/journal/JournalEditor.vue";
import RecurringTab from "@/components/journal/RecurringTab.vue";
import { Button } from "@/components/ui/button";
import { useDeleteMasterRow, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { useTabParam } from "@/composables/useTabParam";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, yearStart } from "@/lib/format";
import { useAuthStore } from "@/stores/auth";

const { t, tm } = useI18n();
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const { can } = usePermissions();
const serverError = useServerError();

const TABS = ["journals", "recurring"] as const;
const tab = useTabParam(() => TABS);
const tabs = computed(() => [
  { key: "journals" as const, label: t("journals.tabs.journals"), icon: BookOpen },
  { key: "recurring" as const, label: t("journals.tabs.recurring"), icon: Repeat },
]);

const from = ref(yearStart());
const to = ref(`${new Date().getFullYear()}-12-31`);
const kind = ref<string | null>(null);
const KIND_OPTIONS = computed(() => Object.keys(tm("journalKinds")).map((k) => ({ value: k, label: t(`journalKinds.${k}`) })));

const journals = useQuery({
  queryKey: computed(() => ["t_journals", "list", from.value, to.value, kind.value]),
  queryFn: async () => {
    let q = supabase
      .from("t_journals")
      .select("*, creator:profiles!t_journals_created_by_fkey(full_name)")
      .gte("journal_date", from.value)
      .lte("journal_date", to.value);
    if (kind.value) q = q.eq("kind", kind.value);
    const { data, error } = await q.order("journal_date", { ascending: false }).order("id", { ascending: false }).limit(1000);
    if (error) throw error;
    return data as unknown as MasterRow[];
  },
});
const rows = computed(() => journals.data.value ?? []);

const editable = (r: MasterRow) =>
  r.status === "draft" && ["manual", "opening"].includes(String(r.kind)) &&
  (can("journal", "update") || (r.created_by === auth.user?.id && can("journal", "create")));
const deletable = (r: MasterRow) =>
  r.status === "draft" && ["manual", "opening"].includes(String(r.kind)) && (can("journal", "delete") || r.created_by === auth.user?.id);
const docNo = (r: MasterRow) => (r.doc_no as string | null) ?? t("journals.draftNo", { id: r.id });
const creator = (r: MasterRow) => (r.creator as { full_name?: string } | null)?.full_name ?? "-";

const editorOpen = ref(false);
const editing = ref<MasterRow | null>(null);
function openEditor(row: MasterRow | null) {
  editing.value = row;
  editorOpen.value = true;
}

const submit = useRpcMutation("submit_journal", ["t_journals", "pending_approvals"]);
async function submitRow(row: MasterRow) {
  try {
    const res = await submit.mutateAsync({ p_id: row.id });
    toast.success(res === "posted" ? t("journals.postedToast") : t("journals.submittedToast"));
  } catch (err) {
    toast.error(serverError(err));
  }
}
const remove = useDeleteMasterRow("t_journals");
const deleting = ref<MasterRow | null>(null);
async function confirmDelete() {
  try {
    await remove.mutateAsync(deleting.value!.id);
    deleting.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}

const detailId = ref<number | null>(Number(route.query.id) || null);
watch(() => route.query.id, (v) => (detailId.value = Number(v) || null));
watch(detailId, (v) => {
  if (String(v ?? "") !== String(route.query.id ?? "")) router.replace({ query: { ...route.query, id: v ?? undefined } });
});

const exportRows = () =>
  rows.value.map((r) => ({
    [t("journals.docNo")]: docNo(r),
    [t("common.date")]: r.journal_date,
    [t("journals.kind")]: t(`journalKinds.${r.kind}`),
    [t("journals.memo")]: r.memo ?? "",
    [t("common.reference")]: r.reference ?? "",
    [t("common.total")]: r.total,
    [t("common.status")]: t(`status.${r.status}`),
    [t("common.createdBy")]: creator(r),
  }));
</script>

<template>
  <div class="space-y-6">
    <TabBar v-model="tab" :tabs="tabs" />
    <div v-if="tab === 'journals'" class="space-y-3">
      <div class="flex flex-wrap items-center gap-2">
        <PeriodFilter v-model:from="from" v-model:to="to" />
        <AppSelect v-model="kind" :options="KIND_OPTIONS" :null-label="t('journals.allKinds')" class="w-48" :aria-label="t('journals.kind')" />
      </div>
      <DocTable
        :title="t('journals.title')"
        :columns="[t('journals.docNo'), t('common.date'), t('journals.kind'), t('journals.memo'), t('common.reference'), t('common.total'), t('common.status'), t('common.createdBy'), '']"
        :rows="rows"
        :pending="journals.isPending.value"
        :failed="journals.isError.value"
        :status-label="(s: string) => t(`status.${s}`)"
        @retry="journals.refetch()"
      >
        <template #toolbar>
          <ExportMenu name="jurnal" :title="t('journals.title')" :rows="exportRows" :disabled="!rows.length" />
          <Button v-if="can('journal', 'create')" size="sm" @click="openEditor(null)"><Plus /> {{ t("journals.new") }}</Button>
        </template>
        <template #row="{ row }">
          <td>
            <button type="button" class="text-primary-text font-mono text-xs whitespace-nowrap hover:underline" @click="detailId = row.id">{{ docNo(row) }}</button>
          </td>
          <td class="whitespace-nowrap tabular-nums">{{ formatDate(row.journal_date as string) }}</td>
          <td class="whitespace-nowrap">{{ t(`journalKinds.${row.kind}`) }}</td>
          <td class="min-w-64">
            {{ row.memo || "-" }}
            <p v-if="row.status === 'draft' && row.reject_reason" class="text-xs text-rose-700 dark:text-rose-400">
              {{ t("journals.rejected", { reason: row.reject_reason }) }}
            </p>
          </td>
          <td>{{ row.reference || "-" }}</td>
          <td class="text-right whitespace-nowrap tabular-nums">{{ Number(row.total) ? formatMoney(row.total) : "-" }}</td>
          <td><DocStatus :status="row.status as string" /></td>
          <td class="whitespace-nowrap">{{ creator(row) }}</td>
          <td>
            <div class="flex justify-end gap-1">
              <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="detailId = row.id"><Info /></Button>
              <template v-if="editable(row)">
                <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openEditor(row)"><Pencil /></Button>
                <Button
                  variant="soft" size="icon" class="size-8" :tooltip="t('journals.submit')" :disabled="submit.isPending.value"
                  :loading="submit.isPending.value && submit.variables.value?.p_id === row.id" @click="submitRow(row)"
                >
                  <Send />
                </Button>
              </template>
              <Button v-if="deletable(row)" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')" @click="deleting = row"><Trash2 /></Button>
            </div>
          </td>
        </template>
      </DocTable>
    </div>
    <RecurringTab v-else @open-journal="detailId = $event" />

    <JournalEditor v-model:open="editorOpen" :journal="editing" />
    <JournalDetail v-model:id="detailId" />
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
  </div>
</template>
