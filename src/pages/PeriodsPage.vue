<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ArrowRight, CalendarPlus, Check, Lock, LockOpen, RefreshCw, Scale } from "@lucide/vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useServerError } from "@/composables/useServerError";
import { formatMoney } from "@/lib/format";

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const years = useMasterRows("m_fiscal_years", { order: "year", descending: true });
const periods = useMasterRows("m_periods", { order: "start_date" });
const periodsOf = (yearId: number) => (periods.data.value ?? []).filter((p) => p.fiscal_year_id === yearId);
const monthLabel = (p: MasterRow) => new Date(`${p.start_date}T00:00`).toLocaleDateString("id-ID", { month: "long" });

const selectedId = ref<number | null>(null);
watch(
  () => periods.data.value,
  (rows) => {
    if (selectedId.value == null && rows?.length) selectedId.value = (rows.find((p) => p.status === "open") ?? rows.at(-1))!.id;
  },
  { immediate: true },
);
const selected = computed(() => periods.data.value?.find((p) => p.id === selectedId.value));
const checklist = useRpcQuery("period_checklist", () => (selectedId.value ? { p_period_id: selectedId.value } : null));
const openItems = computed(() => (checklist.data.value ?? []).filter((i) => Number(i.count) > 0));

const REFRESH = ["m_periods", "m_fiscal_years", "period_checklist", "t_journals", "general_ledger", "trial_balance"];
const closePeriod = useRpcMutation("close_period", REFRESH);
const reopenPeriod = useRpcMutation("reopen_period", REFRESH);
const revalue = useRpcMutation("revalue_fx", REFRESH);
const closeYear = useRpcMutation("close_fiscal_year", REFRESH);
const reopenYear = useRpcMutation("reopen_fiscal_year", REFRESH);
const openYear = useRpcMutation("open_fiscal_year", REFRESH);
const nextYear = computed(() => Number(years.data.value?.[0]?.year ?? new Date().getFullYear() - 1) + 1);

const pending = ref<{ title: string; description: string; destructive?: boolean; run: () => Promise<string> } | null>(null);
const busy = ref(false);
async function confirm() {
  if (!pending.value) return;
  busy.value = true;
  try {
    toast.success(await pending.value.run());
    pending.value = null;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    busy.value = false;
  }
}
const done = t("periods.done");
const ask = {
  closePeriod: (p: MasterRow) => (pending.value = {
    title: `${t("periods.actions.closePeriod")} ${monthLabel(p)}?`, description: t("periods.actions.closePeriodHint"),
    run: async () => (await closePeriod.mutateAsync({ p_period_id: p.id }), done),
  }),
  reopenPeriod: (p: MasterRow) => (pending.value = {
    title: `${t("periods.actions.reopenPeriod")} ${monthLabel(p)}?`, description: t("periods.actions.reopenPeriodHint"), destructive: true,
    run: async () => (await reopenPeriod.mutateAsync({ p_period_id: p.id }), done),
  }),
  revalue: (p: MasterRow) => (pending.value = {
    title: `${t("periods.actions.revalue")} ${monthLabel(p)}?`, description: t("periods.actions.revalueHint"),
    run: async () => {
      const res = (await revalue.mutateAsync({ p_date: String(p.end_date) })) as { lines?: number; net?: number };
      return res.lines ? t("periods.revalueResult", { lines: res.lines, net: formatMoney(res.net) }) : t("periods.revalueNone");
    },
  }),
  closeYear: (y: MasterRow) => (pending.value = {
    title: `${t("periods.actions.closeYear")} ${y.year}?`, description: t("periods.actions.closeYearHint"),
    run: async () => (await closeYear.mutateAsync({ p_year_id: y.id }), done),
  }),
  reopenYear: (y: MasterRow) => (pending.value = {
    title: `${t("periods.actions.reopenYear")} ${y.year}?`, description: t("periods.actions.reopenYearHint"), destructive: true,
    run: async () => (await reopenYear.mutateAsync({ p_year_id: y.id }), done),
  }),
  openYear: () => (pending.value = {
    title: `${t("periods.actions.openYear", { year: nextYear.value })}?`, description: t("periods.actions.openYearHint"),
    run: async () => (await openYear.mutateAsync({ p_year: nextYear.value }), done),
  }),
};

const periodActions = computed(() => {
  const p = selected.value;
  if (!p) return [];
  const yearOpen = years.data.value?.find((y) => y.id === p.fiscal_year_id)?.status === "open";
  return [
    { key: "revalue", show: p.status === "open" && can("period", "update"), icon: Scale, label: t("periods.actions.revalue"), hint: t("periods.actions.revalueHint"), run: () => ask.revalue(p) },
    { key: "close", show: p.status === "open" && can("period", "update"), icon: Lock, label: t("periods.actions.closePeriod"), hint: t("periods.actions.closePeriodHint"), run: () => ask.closePeriod(p) },
    { key: "reopen", show: p.status === "closed" && yearOpen && can("period", "delete"), icon: LockOpen, label: t("periods.actions.reopenPeriod"), hint: t("periods.actions.reopenPeriodHint"), run: () => ask.reopenPeriod(p) },
  ].filter((a) => a.show);
});
</script>

<template>
  <div class="space-y-6">
    <div class="toolbar">
      <p class="text-muted-foreground mr-auto text-sm">{{ t("periods.pickPeriod") }}</p>
      <Button v-if="can('period', 'update') && years.data.value" size="sm" variant="outline" :tooltip="t('periods.actions.openYearHint')" @click="ask.openYear()">
        <CalendarPlus /> {{ t("periods.actions.openYear", { year: nextYear }) }}
      </Button>
    </div>

    <LoadingState v-if="years.isPending.value || periods.isPending.value" variant="cards" />
    <EmptyState v-else-if="years.isError.value || periods.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="(years.refetch(), periods.refetch())"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!years.data.value?.length" :title="t('common.empty')" />
    <div v-else class="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_24rem]">
      <div class="space-y-6">
        <section v-for="y in years.data.value" :key="y.id" class="bg-card space-y-4 rounded-xl border p-4">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="font-semibold">{{ t("periods.fiscalYear", { year: y.year }) }}</h2>
            <DocStatus :status="y.status as string" />
            <div class="ml-auto flex flex-wrap gap-2">
              <Button v-if="y.status === 'open' && can('period', 'delete')" size="sm" variant="outline" :tooltip="t('periods.actions.closeYearHint')" @click="ask.closeYear(y)">
                <Lock /> {{ t("periods.actions.closeYear") }}
              </Button>
              <Button v-if="y.status === 'closed' && can('period', 'delete')" size="sm" variant="ghost-destructive" :tooltip="t('periods.actions.reopenYearHint')" @click="ask.reopenYear(y)">
                <LockOpen /> {{ t("periods.actions.reopenYear") }}
              </Button>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-6">
            <button
              v-for="p in periodsOf(y.id)"
              :key="p.id"
              type="button"
              :aria-pressed="p.id === selectedId"
              :class="[
                'flex flex-col items-start gap-1.5 rounded-xl border p-3 text-left transition-colors',
                p.id === selectedId ? 'border-primary bg-primary-soft' : 'hover:border-primary/60',
              ]"
              @click="selectedId = p.id"
            >
              <span class="text-sm font-medium capitalize">{{ monthLabel(p) }}</span>
              <DocStatus :status="p.status as string" />
            </button>
          </div>
        </section>
      </div>

      <aside v-if="selected" class="bg-card space-y-4 rounded-xl border p-4 xl:sticky xl:top-4">
        <div class="flex items-center gap-2">
          <h2 class="font-semibold capitalize">{{ monthLabel(selected) }} {{ String(selected.start_date).slice(0, 4) }}</h2>
          <DocStatus :status="selected.status as string" />
        </div>

        <div class="space-y-2">
          <h3 class="text-muted-foreground text-xs font-medium">{{ t("periods.checklist") }}</h3>
          <LoadingState v-if="checklist.isPending.value" variant="list" :rows="4" />
          <EmptyState v-else-if="checklist.isError.value" compact :title="t('common.loadFailed')">
            <Button variant="outline" size="sm" @click="checklist.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
          </EmptyState>
          <template v-else>
            <p v-if="!openItems.length" class="flex items-center gap-2 rounded-lg bg-green-500/15 px-3 py-2 text-sm text-green-700 dark:text-green-400">
              <Check class="size-4" /> {{ t("periods.allClear") }}
            </p>
            <ul class="divide-y divide-dashed">
              <li v-for="i in checklist.data.value" :key="i.item" class="flex items-center gap-2 py-2 text-sm">
                <span :class="['min-w-0 flex-1', Number(i.count) === 0 && 'text-muted-foreground']">
                  {{ t(`periods.items.${i.item}`) }}
                  <span v-if="i.blocking && Number(i.count) > 0" class="block text-xs text-rose-700 dark:text-rose-400">{{ t("periods.blocking") }}</span>
                </span>
                <Check v-if="Number(i.count) === 0" class="size-4 text-green-600" />
                <template v-else>
                  <span
                    :class="['rounded-md px-2 py-0.5 text-xs font-semibold tabular-nums', i.blocking ? 'bg-rose-500/10 text-rose-700 dark:text-rose-400' : 'bg-orange-100 text-orange-700 dark:bg-orange-500/15 dark:text-orange-300']"
                  >
                    {{ i.count }}
                  </span>
                  <Button as-child variant="ghost" size="icon" class="size-8" :tooltip="t('periods.open')">
                    <RouterLink :to="i.link"><ArrowRight /></RouterLink>
                  </Button>
                </template>
              </li>
            </ul>
          </template>
        </div>

        <div v-if="periodActions.length" class="space-y-3 border-t border-dashed pt-4">
          <div v-for="a in periodActions" :key="a.key" class="space-y-1">
            <Button size="sm" :variant="a.key === 'reopen' ? 'ghost-destructive' : a.key === 'close' ? 'default' : 'outline'" class="active:scale-95" @click="a.run()">
              <component :is="a.icon" /> {{ a.label }}
            </Button>
            <p class="text-muted-foreground text-xs">{{ a.hint }}</p>
          </div>
        </div>
      </aside>
    </div>

    <ConfirmDialog
      :open="!!pending"
      :title="pending?.title ?? ''"
      :description="pending?.description"
      :confirm-label="t('common.confirm')"
      :busy="busy"
      :destructive="pending?.destructive"
      @update:open="!busy && (pending = null)"
      @confirm="confirm"
    />
  </div>
</template>
