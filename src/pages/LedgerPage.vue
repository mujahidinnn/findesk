<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { Info, RefreshCw } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import JournalDetail from "@/components/journal/JournalDetail.vue";
import { Button } from "@/components/ui/button";
import { useAccountOptions, useSimpleOptions } from "@/composables/useLookups";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { accountName } from "@/lib/accountName";
import { formatAmount, formatDate, formatMoney, isoDate, yearStart } from "@/lib/format";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const { rows: accountRows, options: accountOptions } = useAccountOptions();
const { options: costCenters } = useSimpleOptions("m_cost_centers");

const accountId = ref<number | null>(Number(route.query.account) || null);
watch(() => route.query.account, (v) => (accountId.value = Number(v) || null));
watch(accountId, (v) => {
  if (String(v ?? "") !== String(route.query.account ?? "")) router.replace({ query: { ...route.query, account: v ?? undefined } });
});
const from = ref(yearStart());
const to = ref(isoDate());
const costCenterId = ref<number | null>(null);

const account = computed(() => accountRows.data.value?.find((a) => a.id === accountId.value));
const ledger = useRpcQuery("general_ledger", () =>
  accountId.value
    ? { p_account_id: accountId.value, p_from: from.value, p_to: to.value, ...(costCenterId.value && { p_cost_center_id: costCenterId.value }) }
    : null,
);
const rows = computed(() => ledger.data.value ?? []);
const lines = computed(() => rows.value.filter((r) => r.line_id != null));
const hasFx = computed(() => lines.value.some((r) => r.currency));
const summary = computed(() => ({
  opening: Number(rows.value[0]?.balance ?? 0),
  debit: lines.value.reduce((s, r) => s + Number(r.debit), 0),
  credit: lines.value.reduce((s, r) => s + Number(r.credit), 0),
  closing: Number(rows.value.at(-1)?.balance ?? 0),
}));
const cards = computed(() => [
  { key: "opening", label: t("ledger.opening"), value: summary.value.opening },
  { key: "debit", label: t("ledger.totalDebit"), value: summary.value.debit },
  { key: "credit", label: t("ledger.totalCredit"), value: summary.value.credit },
  { key: "closing", label: t("ledger.closing"), value: summary.value.closing },
]);

const detailId = ref<number | null>(null);
const exportRows = () =>
  rows.value.map((r) => ({
    [t("common.date")]: r.journal_date,
    [t("ledger.docNo")]: r.doc_no ?? "",
    [t("ledger.kind")]: r.line_id == null ? t("ledger.opening") : t(`journalKinds.${r.kind}`),
    [t("ledger.memo")]: r.memo ?? "",
    [t("common.partner")]: r.partner ?? "",
    [t("common.costCenter")]: r.cost_center ?? "",
    ...(hasFx.value && { [t("ledger.foreign")]: r.fc_amount == null ? "" : `${r.currency} ${r.fc_amount}` }),
    [t("common.debit")]: r.debit,
    [t("common.credit")]: r.credit,
    [t("common.balance")]: r.balance,
  }));
const num = "text-right whitespace-nowrap tabular-nums";
</script>

<template>
  <div class="space-y-4">
    <div class="toolbar">
      <SearchSelect v-model="accountId" :options="accountOptions" :placeholder="t('ledger.pickAccount')" class="w-full sm:w-80" :aria-label="t('ledger.account')" />
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <SearchSelect v-model="costCenterId" :options="costCenters" :null-label="t('ledger.allCostCenters')" class="w-52" :aria-label="t('common.costCenter')" />
      <ExportMenu
        class="ml-auto" :name="`buku-besar-${account?.code ?? ''}`" :title="`${account?.code ?? ''} ${account ? accountName(String(account.code), String(account.name)) : ''}`"
        :rows="exportRows" :disabled="!rows.length"
      />
    </div>

    <EmptyState v-if="!accountId" :title="t('ledger.pickAccount')" />
    <template v-else>
      <p v-if="account?.currency" class="bg-primary-soft text-primary-text rounded-lg px-3 py-2 text-sm">
        {{ t("ledger.fxNote", { currency: account.currency }) }}
      </p>
      <LoadingState v-if="ledger.isPending.value" variant="cards" :rows="4" />
      <div v-else-if="!ledger.isError.value" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div v-for="c in cards" :key="c.key" class="bg-card rounded-xl border p-4">
          <p class="text-muted-foreground text-xs">{{ c.label }}</p>
          <p class="mt-1 text-xl font-semibold tabular-nums">{{ formatAmount(c.value) }}</p>
        </div>
      </div>

      <LoadingState v-if="ledger.isPending.value" :columns="hasFx ? 10 : 9" />
      <EmptyState v-else-if="ledger.isError.value" :title="t('common.loadFailed')">
        <Button variant="outline" size="sm" @click="ledger.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
      </EmptyState>
      <div v-else class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr>
              <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("ledger.docNo") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("ledger.kind") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("ledger.memo") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("common.partner") }}</th>
              <th class="px-3 py-2 font-medium">{{ t("common.costCenter") }}</th>
              <th v-if="hasFx" class="px-3 py-2 text-right font-medium">{{ t("ledger.foreign") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("common.debit") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("common.credit") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("common.balance") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rows" :key="r.line_id ?? 'opening'" :class="['border-b last:border-0 [&>td]:px-3 [&>td]:py-2', r.line_id == null && 'bg-secondary/40 font-medium']">
              <td class="whitespace-nowrap tabular-nums">{{ formatDate(r.journal_date) }}</td>
              <td>
                <button v-if="r.journal_id" type="button" class="text-primary-text inline-flex items-center gap-1 font-mono text-xs whitespace-nowrap hover:underline" @click="detailId = r.journal_id">
                  {{ r.doc_no }} <Info class="size-3" />
                </button>
              </td>
              <td class="whitespace-nowrap">{{ r.line_id == null ? t("ledger.opening") : t(`journalKinds.${r.kind}`) }}</td>
              <td>{{ r.line_id == null ? "" : r.memo }}</td>
              <td>{{ r.partner }}</td>
              <td class="font-mono text-xs">{{ r.cost_center }}</td>
              <td v-if="hasFx" :class="num">{{ r.fc_amount == null ? "" : formatMoney(r.fc_amount, String(r.currency)) }}</td>
              <td :class="num">{{ r.line_id == null ? "" : formatAmount(r.debit) }}</td>
              <td :class="num">{{ r.line_id == null ? "" : formatAmount(r.credit) }}</td>
              <td :class="[num, 'font-medium']">{{ formatAmount(r.balance) }}</td>
            </tr>
            <tr v-if="!lines.length">
              <td :colspan="hasFx ? 10 : 9" class="text-muted-foreground px-3 py-6 text-center text-sm">{{ t("ledger.noMovement") }}</td>
            </tr>
          </tbody>
          <tfoot v-if="lines.length" class="border-t font-semibold">
            <tr class="[&>td]:px-3 [&>td]:py-2">
              <td :colspan="hasFx ? 7 : 6">{{ t("ledger.closing") }}</td>
              <td :class="num">{{ formatAmount(summary.debit) }}</td>
              <td :class="num">{{ formatAmount(summary.credit) }}</td>
              <td :class="num">{{ formatAmount(summary.closing) }}</td>
            </tr>
          </tfoot>
        </table>
      </div>
    </template>
    <JournalDetail v-model:id="detailId" />
  </div>
</template>
