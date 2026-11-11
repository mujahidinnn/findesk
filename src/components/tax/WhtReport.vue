<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { RefreshCw } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { Button } from "@/components/ui/button";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, formatMoney, isoDate, monthStart, round2 } from "@/lib/format";

const { t } = useI18n();
const from = ref(monthStart());
const to = ref(isoDate());
const report = useRpcQuery("wht_report", () => ({ p_from: from.value, p_to: to.value }));
type Row = NonNullable<typeof report.data.value>[number];
const total = (rows: Row[], k: "gross" | "wht") => round2(rows.reduce((s, r) => s + Number(r[k]), 0));

const sections = computed(() =>
  (["withheld_by_us", "withheld_from_us"] as const).map((side) => {
    const rows = (report.data.value ?? []).filter((r) => r.side === side);
    const groups = [...new Set(rows.map((r) => r.wht_type))].sort().map((type) => ({ type, rows: rows.filter((r) => r.wht_type === type) }));
    return { side, rows, groups };
  }),
);
const docLink = (r: Row) => ({ path: r.side === "withheld_by_us" ? "/purchases/bills" : "/sales/receipts", query: { id: String(r.doc_id) } });
const exportRows = () =>
  (report.data.value ?? []).map((r) => ({
    [t("tax.wht.side")]: t(`tax.wht.${r.side}`), [t("tax.wht.type")]: t(`tax.whtTypes.${r.wht_type}`), [t("tax.code")]: r.tax_code,
    [t("tax.docNo")]: r.doc_no, [t("common.date")]: r.doc_date, [t("common.partner")]: r.partner, NPWP: r.npwp,
    [t("tax.wht.slipNo")]: r.slip_no, [t("tax.wht.gross")]: r.gross, PPh: r.wht,
  }));
</script>

<template>
  <div class="space-y-4">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("tax.wht.title") }}</h2>
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <ExportMenu :name="`pph-${from}-${to}`" :title="t('tax.wht.title')" :rows="exportRows" :disabled="!report.data.value?.length" />
    </div>

    <LoadingState v-if="report.isPending.value" />
    <EmptyState v-else-if="report.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="report.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <template v-else>
      <section v-for="s in sections" :key="s.side" class="space-y-2">
        <div class="flex flex-wrap items-baseline gap-x-4">
          <h3 class="mr-auto text-sm font-semibold">{{ t(`tax.wht.${s.side}`) }}</h3>
          <p class="text-sm tabular-nums">
            <span class="text-muted-foreground">{{ t("common.total") }}</span> <span class="font-semibold">{{ formatMoney(total(s.rows, "wht")) }}</span>
          </p>
        </div>
        <p class="text-muted-foreground text-xs">{{ t(`tax.wht.${s.side}Hint`) }}</p>
        <EmptyState v-if="!s.rows.length" compact :title="t('common.empty')" />
        <div v-for="g in s.groups" :key="g.type" class="bg-card overflow-x-auto rounded-xl border">
          <div class="flex flex-wrap items-center gap-2 border-b px-3 py-2 text-sm">
            <span class="mr-auto font-medium">{{ t(`tax.whtTypes.${g.type}`) }}</span>
            <span class="text-muted-foreground tabular-nums">{{ t("tax.wht.gross") }} {{ formatMoney(total(g.rows, "gross")) }}</span>
            <span class="font-semibold tabular-nums">PPh {{ formatMoney(total(g.rows, "wht")) }}</span>
          </div>
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="px-3 py-2 font-medium">{{ t("tax.docNo") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.partner") }}</th>
                <th class="px-3 py-2 font-medium">NPWP</th>
                <th class="px-3 py-2 font-medium">{{ t("tax.code") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("tax.wht.slipNo") }}</th>
                <th class="px-3 py-2 text-right font-medium">{{ t("tax.wht.gross") }}</th>
                <th class="px-3 py-2 text-right font-medium">PPh</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in g.rows" :key="`${r.doc_id}-${r.tax_code}`" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                <td class="font-mono text-xs whitespace-nowrap">
                  <RouterLink :to="docLink(r)" class="text-primary-text hover:underline">{{ r.doc_no }}</RouterLink>
                </td>
                <td class="whitespace-nowrap">{{ formatDate(r.doc_date) }}</td>
                <td>{{ r.partner }}</td>
                <td class="font-mono text-xs">{{ r.npwp }}</td>
                <td class="font-mono text-xs">{{ r.tax_code }}</td>
                <td class="font-mono text-xs">{{ r.slip_no ?? "-" }}</td>
                <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(r.gross) }}</td>
                <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(r.wht) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
