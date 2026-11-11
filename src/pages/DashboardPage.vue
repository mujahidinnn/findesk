<script setup lang="ts">
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { keepPreviousData, useQuery } from "@tanstack/vue-query";
import {
  ArrowRight, BookOpen, ChartPie, Clock, FileInput, Gauge, HandCoins, Landmark, Percent, Receipt, RefreshCw, ShieldCheck, TrendingDown, TrendingUp, Wallet,
} from "@lucide/vue";
import BarChart from "@/components/charts/BarChart.vue";
import DonutChart from "@/components/charts/DonutChart.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import ColumnChart from "@/components/dashboard/ColumnChart.vue";
import { Button } from "@/components/ui/button";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { usePermissions } from "@/composables/usePermissions";
import { supabase } from "@/integrations/supabase/client";
import { formatMoney, isoDate, monthStart } from "@/lib/format";

interface Summary {
  cash: number; receivable: number; receivable_overdue: number; payable: number; payable_overdue: number;
  revenue: number; expense: number; net_income: number; gross_margin_pct: number | null; current_ratio: number | null;
  dso: number | null; dpo: number | null; pending_approvals: number;
  banks: { id: number; code: string; name: string; kind: string; currency: string; base: number; fc: number }[];
  monthly: { month: string; revenue: number; expense: number; net: number }[];
  cash_monthly: { month: string; in: number; out: number }[];
  expense_breakdown: { name: string; amount: number }[];
  top_customers: { name: string; amount: number }[];
  forecast: { bucket: "d0_7" | "d8_30" | "d31_60" | "d61_90"; in: number; out: number }[];
}

const { t, locale } = useI18n();
const { can } = usePermissions();
const from = ref(monthStart());
const to = ref(isoDate());

const summary = useQuery({
  queryKey: computed(() => ["dashboard_summary", from.value, to.value]),
  placeholderData: keepPreviousData,
  queryFn: async () => {
    const { data, error } = await supabase.rpc("dashboard_summary", { p_from: from.value, p_to: to.value });
    if (error) throw error;
    return data as unknown as Summary;
  },
});
const s = computed(() => summary.data.value);
const monthEnd = useRpcQuery("cash_month_end", () => ({ p_to: to.value, p_months: 12 }));
const trend = computed(() => {
  const rows = monthEnd.data.value ?? [];
  if (rows.length < 2) return null;
  const bal = rows.map((r) => Number(r.balance));
  const min = Math.min(...bal), max = Math.max(...bal), span = max - min || 1;
  const x = (i: number) => (i / (bal.length - 1)) * 100;
  const y = (v: number) => 8 + (1 - (v - min) / span) * 84;
  const label = (m: string, long = false) => new Date(`${m}-01T00:00`).toLocaleDateString(locale.value === "en" ? "en-US" : "id-ID", { month: "short", ...(long && { year: "numeric" }) });
  const last = bal.length - 1;
  return {
    line: `M${bal.map((v, i) => `${(x(i) * 6).toFixed(1)},${(y(v) * 1.2).toFixed(1)}`).join(" L")}`,
    points: rows.map((r, i) => ({ key: r.month, x: x(i), y: y(bal[i]!), label: label(r.month), tip: `${label(r.month, true)}: ${rp(bal[i])}`, show: i === 0 || i === last || i % 2 === 0 })),
    delta: bal[last]! - bal[last - 1]!,
    prev: label(rows[last - 1]!.month),
  };
});

const rp = (n: unknown) => formatMoney(Number(n ?? 0));
const compact = new Intl.NumberFormat("id-ID", { notation: "compact", maximumFractionDigits: 1 });
const rpShort = (n: number) => `Rp\u00a0${compact.format(n)}`;
const month = (ym: string) => new Date(`${ym}-01T00:00`).toLocaleDateString("id-ID", { month: "short" });
const reports = computed(() => can("reports", "read"));
const report = (tab: string) => (reports.value ? `/reports?tab=${tab}` : undefined);

interface Tile { key: string; icon: Component; label: string; value: string; sub?: string; alert?: boolean; href?: string }
const tiles = computed<Tile[]>(() => {
  const m = s.value;
  if (!m) return [];
  const margin = Number(m.revenue) ? Math.round((Number(m.net_income) / Number(m.revenue)) * 1000) / 10 : null;
  return [
    {
      key: "receivable", icon: HandCoins, label: t("dashboard.receivable"), value: rp(m.receivable),
      sub: t("dashboard.overdue", { amount: rp(m.receivable_overdue) }), alert: Number(m.receivable_overdue) > 0,
      href: reports.value ? "/aging?tab=receivable" : can("receivable", "read") ? "/sales/invoices" : undefined,
    },
    {
      key: "payable", icon: FileInput, label: t("dashboard.payable"), value: rp(m.payable),
      sub: t("dashboard.overdue", { amount: rp(m.payable_overdue) }), alert: Number(m.payable_overdue) > 0,
      href: reports.value ? "/aging?tab=payable" : can("payable", "read") ? "/purchases/bills" : undefined,
    },
    { key: "revenue", icon: TrendingUp, label: t("dashboard.revenue"), value: rp(m.revenue), sub: t("dashboard.expenseSub", { amount: rp(m.expense) }), href: report("income") },
    {
      key: "net", icon: Wallet, label: t("dashboard.netIncome"), value: rp(m.net_income), alert: Number(m.net_income) < 0,
      sub: margin == null ? undefined : t("dashboard.netMargin", { n: margin.toLocaleString("id-ID") }), href: report("income"),
    },
  ];
});
const ratios = computed<Tile[]>(() => {
  const m = s.value;
  if (!m) return [];
  const dash = t("common.none");
  return [
    {
      key: "margin", icon: Percent, label: t("dashboard.grossMargin"), href: report("income"), sub: t("dashboard.grossMarginSub"),
      value: m.gross_margin_pct == null ? dash : `${Number(m.gross_margin_pct).toLocaleString("id-ID")}%`,
    },
    {
      key: "ratio", icon: Gauge, label: t("dashboard.currentRatio"), href: report("balance"), sub: t("dashboard.currentRatioSub"),
      value: m.current_ratio == null ? dash : `${Number(m.current_ratio).toLocaleString("id-ID")}×`, alert: m.current_ratio != null && Number(m.current_ratio) < 1,
    },
    { key: "days", icon: Clock, label: t("dashboard.dsoDpo"), href: reports.value ? "/aging" : undefined, value: `${m.dso ?? dash} / ${m.dpo ?? dash}`, sub: t("dashboard.dsoDpoSub") },
  ];
});

const monthLabels = computed(() => (s.value?.monthly ?? []).map((m) => month(m.month)));
const cashLabels = computed(() => (s.value?.cash_monthly ?? []).map((m) => month(m.month)));
const expenseSlices = computed(() => (s.value?.expense_breakdown ?? []).map((e) => ({ label: e.name, value: Number(e.amount) })));
const customerBars = computed(() => (s.value?.top_customers ?? []).map((c) => ({ label: c.name, value: Number(c.amount) })));
const forecast = computed(() => s.value?.forecast ?? []);
const forecastNet = computed(() => forecast.value.reduce((sum, f) => sum + Number(f.in) - Number(f.out), 0));

const actions = computed(() =>
  [
    { key: "invoice", icon: Receipt, to: "/sales/invoices", ok: can("receivable", "create") },
    { key: "bill", icon: FileInput, to: "/purchases/bills", ok: can("payable", "create") },
    { key: "journal", icon: BookOpen, to: "/journals", ok: can("journal", "create") },
  ].filter((a) => a.ok),
);
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center gap-2">
      <PeriodFilter v-model:from="from" v-model:to="to" />
      <div v-if="actions.length" class="flex flex-wrap gap-2 sm:ml-auto">
        <Button v-for="a in actions" :key="a.key" as-child variant="outline" size="sm">
          <RouterLink :to="a.to"><component :is="a.icon" /> {{ t(`dashboard.actions.${a.key}`) }}</RouterLink>
        </Button>
      </div>
    </div>

    <LoadingState v-if="summary.isPending.value" variant="hero" />
    <EmptyState v-else-if="summary.isError.value || !s" class="bg-card rounded-xl border" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="summary.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <template v-else>
      <section class="bg-card grid gap-8 rounded-xl border p-6 sm:p-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)]" :aria-label="t('dashboard.cashPosition')">
        <div class="flex min-w-0 flex-col">
          <p class="text-muted-foreground flex items-center gap-2 text-sm font-medium"><Landmark class="size-4" /> {{ t("dashboard.cashPosition") }}</p>
          <p class="mt-3 text-4xl font-semibold tracking-[-0.035em] tabular-nums break-all sm:text-5xl">{{ rp(s.cash) }}</p>
          <p class="text-muted-foreground mt-1.5 text-sm">{{ t("dashboard.cashAsOf", { date: new Date(`${to}T00:00`).toLocaleDateString("id-ID", { dateStyle: "long" }) }) }}</p>
          <p v-if="trend" :class="['mt-3 flex items-center gap-1 text-sm font-medium tabular-nums', trend.delta < 0 ? 'text-rose-600 dark:text-rose-400' : 'text-success']">
            <component :is="trend.delta < 0 ? TrendingDown : TrendingUp" class="size-4" />
            {{ trend.delta < 0 ? "−" : "+" }}{{ rp(Math.abs(trend.delta)) }}
            <span class="text-muted-foreground font-normal">{{ t("dashboard.cashVs", { month: trend.prev }) }}</span>
          </p>
          <div v-if="trend" class="mt-4 px-3">
            <div class="relative h-28">
              <svg viewBox="0 0 600 120" preserveAspectRatio="none" class="absolute inset-0 size-full" aria-hidden="true">
                <defs>
                  <linearGradient id="cash-trend" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stop-color="var(--color-brand-500)" stop-opacity=".22" />
                    <stop offset="1" stop-color="var(--color-brand-500)" stop-opacity="0" />
                  </linearGradient>
                </defs>
                <path :d="`${trend.line} L600,120 L0,120 Z`" fill="url(#cash-trend)" />
                <path :d="trend.line" fill="none" stroke="var(--color-brand-500)" stroke-width="2" vector-effect="non-scaling-stroke" />
              </svg>
              <div
                v-for="p in trend.points"
                :key="p.key"
                :title="p.tip"
                class="group absolute inset-y-0 w-[7%] -translate-x-1/2"
                :style="{ left: `${p.x}%` }"
              >
                <span class="bg-border absolute inset-y-0 left-1/2 hidden w-px group-hover:block" />
                <span
                  class="bg-card border-brand-500 absolute left-1/2 hidden size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 group-hover:block"
                  :style="{ top: `${p.y}%` }"
                />
              </div>
            </div>
            <div class="text-muted-foreground relative mt-2 h-4 text-[11px]" aria-hidden="true">
              <span v-for="p in trend.points.filter((q) => q.show)" :key="p.key" class="absolute -translate-x-1/2" :style="{ left: `${p.x}%` }">{{ p.label }}</span>
            </div>
          </div>
          <RouterLink v-if="can('cash-bank', 'read')" to="/cash" class="text-primary-text mt-auto flex w-fit items-center gap-1 pt-5 text-sm font-medium hover:underline">
            {{ t("dashboard.openCash") }} <ArrowRight class="size-3.5" />
          </RouterLink>
        </div>
        <ul class="divide-y text-sm lg:border-l lg:pl-8">
          <li v-for="b in s.banks" :key="b.id" class="flex items-baseline gap-3 py-3 first:pt-0">
            <div class="min-w-0 flex-1">
              <p class="truncate font-medium">{{ b.name }}</p>
              <p class="text-muted-foreground font-mono text-[11px]">{{ b.code }} · {{ b.currency }}</p>
            </div>
            <div class="text-right tabular-nums">
              <p class="font-medium">{{ rp(b.base) }}</p>
              <p v-if="b.currency !== 'IDR'" class="text-muted-foreground text-[11px]">{{ formatMoney(b.fc, b.currency) }}</p>
            </div>
          </li>
          <li v-if="!s.banks.length" class="text-muted-foreground py-2">{{ t("dashboard.noBanks") }}</li>
        </ul>
      </section>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <component
          :is="tile.href ? 'RouterLink' : 'div'"
          v-for="tile in tiles"
          :key="tile.key"
          :to="tile.href"
          :class="['bg-card flex flex-col rounded-xl border p-5', tile.href && 'hover:border-input hover:shadow-sm transition']"
        >
          <span class="text-muted-foreground flex items-center gap-2 text-sm font-medium"><component :is="tile.icon" class="size-4" /> {{ tile.label }}</span>
          <span :class="['mt-3 text-2xl font-semibold tracking-[-0.03em] tabular-nums', tile.key === 'net' && tile.alert && 'text-rose-600 dark:text-rose-400']">{{ tile.value }}</span>
          <span v-if="tile.sub" :class="['mt-1 text-xs tabular-nums', tile.alert && tile.key !== 'net' ? 'text-rose-600 dark:text-rose-400' : 'text-muted-foreground']">{{ tile.sub }}</span>
        </component>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <component
          :is="tile.href ? 'RouterLink' : 'div'"
          v-for="tile in ratios"
          :key="tile.key"
          :to="tile.href"
          :class="['bg-card flex items-center gap-3 rounded-xl border p-4', tile.href && 'hover:border-input hover:shadow-sm transition']"
        >
          <span class="bg-secondary text-muted-foreground flex size-9 shrink-0 items-center justify-center rounded-xl"><component :is="tile.icon" class="size-4" /></span>
          <span class="min-w-0 flex-1">
            <span class="text-muted-foreground block truncate text-xs">{{ tile.label }}</span>
            <span :class="['block text-lg font-bold tabular-nums', tile.alert && 'text-rose-600 dark:text-rose-400']">{{ tile.value }}</span>
            <span class="text-muted-foreground block truncate text-[11px]">{{ tile.sub }}</span>
          </span>
        </component>
        <RouterLink
          v-if="can('approval', 'read')"
          to="/approvals"
          :class="['flex items-center gap-3 rounded-xl border p-4 transition-colors', s.pending_approvals ? 'bg-primary-soft border-primary/30 hover:border-primary/60' : 'bg-card hover:border-primary/50']"
        >
          <span class="bg-primary text-primary-foreground flex size-9 shrink-0 items-center justify-center rounded-xl"><ShieldCheck class="size-4" /></span>
          <span class="min-w-0 flex-1">
            <span class="text-muted-foreground block truncate text-xs">{{ t("dashboard.approvals") }}</span>
            <span class="block text-lg font-bold tabular-nums">{{ s.pending_approvals }}</span>
            <span class="text-muted-foreground block truncate text-[11px]">{{ s.pending_approvals ? t("dashboard.approvalsWaiting") : t("dashboard.approvalsClear") }}</span>
          </span>
          <ArrowRight class="text-muted-foreground size-4" />
        </RouterLink>
      </div>

      <div class="grid gap-4 xl:grid-cols-3">
        <section class="bg-card rounded-xl border p-5 xl:col-span-2">
          <h2 class="text-muted-foreground mb-3 text-sm font-medium">{{ t("dashboard.monthly") }}</h2>
          <EmptyState v-if="!s.monthly.length" :title="t('common.empty')" compact />
          <ColumnChart
            v-else
            :labels="monthLabels"
            :series="[
              { label: t('dashboard.revenue'), values: s.monthly.map((m) => Number(m.revenue)), tone: 'fill-chart-1' },
              { label: t('dashboard.expense'), values: s.monthly.map((m) => Number(m.expense)), tone: 'fill-chart-2' },
            ]"
            :line="{ label: t('dashboard.net'), values: s.monthly.map((m) => Number(m.net)), tone: 'stroke-foreground' }"
            :format="rp"
          />
        </section>
        <section class="bg-card flex flex-col rounded-xl border p-5">
          <h2 class="text-muted-foreground mb-3 flex items-center gap-2 text-sm font-medium"><ChartPie class="size-4" /> {{ t("dashboard.expenseBreakdown") }}</h2>
          <EmptyState v-if="!expenseSlices.length" :title="t('common.empty')" compact />
          <DonutChart v-else :rows="expenseSlices" :format="rpShort" class="flex-1 justify-center" />
        </section>
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <section class="bg-card rounded-xl border p-5">
          <h2 class="text-muted-foreground mb-3 text-sm font-medium">{{ t("dashboard.cashFlow") }}</h2>
          <EmptyState v-if="!s.cash_monthly.length" :title="t('common.empty')" compact />
          <ColumnChart
            v-else
            :labels="cashLabels"
            :series="[
              { label: t('dashboard.cashIn'), values: s.cash_monthly.map((m) => Number(m.in)), tone: 'fill-chart-1' },
              { label: t('dashboard.cashOut'), values: s.cash_monthly.map((m) => Number(m.out)), tone: 'fill-chart-2' },
            ]"
            :format="rp"
          />
        </section>
        <section class="bg-card rounded-xl border p-5">
          <div class="mb-3 flex items-baseline justify-between gap-3">
            <h2 class="text-muted-foreground text-sm font-medium">{{ t("dashboard.forecast") }}</h2>
            <span :class="['text-xs font-semibold tabular-nums', forecastNet < 0 ? 'text-rose-600 dark:text-rose-400' : 'text-success']">
              {{ t("dashboard.forecastNet", { amount: rp(forecastNet) }) }}
            </span>
          </div>
          <ColumnChart
            :labels="forecast.map((f) => t(`dashboard.buckets.${f.bucket}`))"
            :series="[
              { label: t('dashboard.expectedIn'), values: forecast.map((f) => Number(f.in)), tone: 'fill-chart-1' },
              { label: t('dashboard.expectedOut'), values: forecast.map((f) => Number(f.out)), tone: 'fill-chart-2' },
            ]"
            :format="rp"
          />
          <p class="text-muted-foreground mt-2 text-[11px]">{{ t("dashboard.forecastHint") }}</p>
        </section>
      </div>

      <section class="bg-card rounded-xl border p-5">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-muted-foreground text-sm font-medium">{{ t("dashboard.topCustomers") }}</h2>
          <RouterLink v-if="can('partner', 'read')" to="/partners" class="text-primary-text text-xs font-medium hover:underline">{{ t("dashboard.seeAll") }}</RouterLink>
        </div>
        <EmptyState v-if="!customerBars.length" :title="t('common.empty')" compact />
        <BarChart v-else :rows="customerBars" :format="rpShort" />
      </section>
    </template>
  </div>
</template>
