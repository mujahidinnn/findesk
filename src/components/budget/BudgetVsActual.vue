<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { RefreshCw } from "@lucide/vue";
import BarChart from "@/components/charts/BarChart.vue";
import AppSelect from "@/components/common/AppSelect.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import type { MasterRow } from "@/composables/useMasterRows";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatAmount, formatMoney } from "@/lib/format";

const props = defineProps<{ budget: MasterRow }>();
const { t, locale } = useI18n();

const start = computed(() => new Date(`${(props.budget.fiscal_year as { start_date?: string } | null)?.start_date ?? `${new Date().getFullYear()}-01-01`}T00:00`));
const monthOptions = computed(() =>
  Array.from({ length: 12 }, (_, i) => ({
    value: i + 1,
    label: new Date(start.value.getFullYear(), start.value.getMonth() + i, 1).toLocaleDateString(locale.value, { month: "long" }),
  })),
);
const from = ref<number | null>(1);
const to = ref<number | null>(12);
const report = useRpcQuery("budget_vs_actual", () =>
  from.value && to.value ? { p_budget_id: props.budget.id, p_from_period: Math.min(from.value, to.value), p_to_period: Math.max(from.value, to.value) } : null,
);
const rows = computed(() => report.data.value ?? []);

const isBad = (r: { account_type: string; budget: number; actual: number }) =>
  r.account_type === "revenue" ? Number(r.actual) < Number(r.budget) : Number(r.actual) > Number(r.budget);

const chart = computed(() =>
  [...rows.value]
    .sort((a, b) => Math.max(Number(b.budget), Number(b.actual)) - Math.max(Number(a.budget), Number(a.actual)))
    .slice(0, 8)
    .map((r) => {
      const b = Number(r.budget);
      const a = Number(r.actual);
      return {
        label: `${r.code} · ${r.name}`,
        value: Math.max(a, b),
        segments: [Math.min(a, b), Math.max(b - a, 0), Math.max(a - b, 0)],
        hint: `${t("budgets.budget")} ${formatMoney(b)} · ${t("budgets.actual")} ${formatMoney(a)}`,
      };
    }),
);
const exportRows = () =>
  rows.value.map((r) => ({
    [t("common.code")]: r.code,
    [t("common.account")]: r.name,
    [t("budgets.budget")]: Number(r.budget),
    [t("budgets.actual")]: Number(r.actual),
    [t("budgets.variance")]: Number(r.variance),
    [t("budgets.used")]: r.used_pct == null ? "" : Number(r.used_pct),
  }));
</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("budgets.tabs.actual") }}</h2>
      <AppSelect v-model="from" :options="monthOptions" class="w-36" :aria-label="t('common.from')" />
      <span class="text-muted-foreground text-xs">–</span>
      <AppSelect v-model="to" :options="monthOptions" class="w-36" :aria-label="t('common.to')" />
      <ExportMenu :name="`anggaran-${budget.id}`" :title="String(budget.name)" :rows="exportRows" :disabled="!rows.length" />
    </div>

    <LoadingState v-if="report.isPending.value" />
    <EmptyState v-else-if="report.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="report.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!rows.length" :title="t('budgets.noLines')" />
    <template v-else>
      <div class="bg-card rounded-xl border p-4">
        <h3 class="mb-3 text-sm font-semibold">{{ t("budgets.topAccounts") }}</h3>
        <BarChart :rows="chart" :legend="[t('budgets.legendUsed'), t('budgets.legendLeft'), t('budgets.legendOver')]" :format="(n: number) => formatMoney(n)" />
      </div>
      <div class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr>
              <th class="px-3 py-2 font-medium">{{ t("common.account") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("budgets.budget") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("budgets.actual") }}</th>
              <th class="px-3 py-2 text-right font-medium">{{ t("budgets.variance") }}</th>
              <th class="w-48 px-3 py-2 font-medium">{{ t("budgets.used") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in rows" :key="r.account_id" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
              <td>
                <RouterLink :to="`/ledger?account=${r.account_id}`" class="hover:underline"><span class="font-mono text-xs">{{ r.code }}</span> {{ r.name }}</RouterLink>
                <span class="text-muted-foreground block text-[11px]">{{ t(`budgets.types.${r.account_type}`) }}</span>
              </td>
              <td class="text-right tabular-nums">{{ formatAmount(r.budget) }}</td>
              <td class="text-right tabular-nums">{{ formatAmount(r.actual) }}</td>
              <td :class="['text-right tabular-nums', isBad(r) && 'text-rose-600']">{{ formatAmount(r.variance) }}</td>
              <td>
                <div class="flex items-center gap-2">
                  <div class="bg-secondary h-2 flex-1 overflow-hidden rounded-full">
                    <div :class="['h-full rounded-full', isBad(r) ? 'bg-rose-500' : 'bg-primary']" :style="{ width: `${Math.min(100, Math.max(0, Number(r.used_pct ?? 0)))}%` }" />
                  </div>
                  <span :class="['w-14 text-right text-xs tabular-nums', isBad(r) && 'text-rose-600']">{{ r.used_pct == null ? "-" : `${Number(r.used_pct).toLocaleString("id-ID")}%` }}</span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>
