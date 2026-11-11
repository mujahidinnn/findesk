<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { RefreshCw } from "@lucide/vue";
import LineChart from "@/components/charts/LineChart.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatDate, formatMoney } from "@/lib/format";

const asset = defineModel<MasterRow | null>("asset", { required: true });
const props = defineProps<{ accumulated: number }>();
const { t } = useI18n();
const { can } = usePermissions();

const schedule = useRpcQuery("asset_schedule", () => (asset.value ? { p_id: asset.value.id } : null));
const rows = computed(() => schedule.data.value ?? []);
const points = computed(() => rows.value.map((r) => ({ date: r.month, value: Number(r.book_value) })));
const month = (iso: string) => new Date(`${iso}T00:00`).toLocaleDateString("id-ID", { month: "short", year: "numeric" });
const facts = computed(() => {
  const a = asset.value;
  if (!a) return [];
  return [
    [t("assets.category"), (a.category as { name?: string } | null)?.name],
    [t("assets.method"), t(`assets.methods.${a.method}`)],
    [t("assets.lifeMonths"), a.useful_life_months],
    [t("assets.acquired"), formatDate(a.acquisition_date as string)],
    [t("assets.inService"), formatDate(a.in_service_date as string)],
    [t("assets.cost"), formatMoney(a.cost)],
    [t("assets.salvage"), formatMoney(a.salvage_value)],
    [t("assets.accumulated"), formatMoney(props.accumulated)],
    [t("assets.bookValue"), a.status === "disposed" ? "-" : formatMoney(Number(a.cost) - props.accumulated)],
    ...(a.status === "disposed"
      ? [
          [t("assets.disposalDate"), formatDate(a.disposal_date as string)],
          [t("assets.proceeds"), formatMoney(a.disposal_proceeds)],
        ]
      : []),
  ].filter(([, v]) => v != null && v !== "");
});
</script>

<template>
  <Dialog :open="!!asset" @update:open="(v) => !v && (asset = null)">
    <DialogContent class="sm:max-w-3xl">
      <DialogHeader>
        <DialogTitle class="flex flex-wrap items-center gap-2">
          <span class="font-mono text-sm">{{ asset?.code }}</span> {{ asset?.name }}
          <DocStatus v-if="asset" :status="String(asset.status)" />
        </DialogTitle>
      </DialogHeader>
      <div class="max-h-[75vh] space-y-4 overflow-y-auto p-1">
        <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-3">
          <div v-for="[k, v] in facts" :key="String(k)">
            <dt class="text-muted-foreground text-xs">{{ k }}</dt>
            <dd class="tabular-nums">{{ v }}</dd>
          </div>
        </dl>
        <RouterLink
          v-if="asset?.disposal_journal_id && can('journal', 'read')"
          :to="`/journals?id=${asset.disposal_journal_id}`"
          class="text-primary-text text-sm hover:underline"
        >
          {{ t("common.openJournal") }}
        </RouterLink>

        <section class="space-y-2 border-t border-dashed pt-3">
          <h3 class="text-sm font-semibold">{{ t("assets.schedule") }}</h3>
          <LoadingState v-if="schedule.isPending.value" variant="line" />
          <EmptyState v-else-if="schedule.isError.value" compact :title="t('common.loadFailed')">
            <Button variant="outline" size="sm" @click="schedule.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
          </EmptyState>
          <EmptyState v-else-if="!rows.length" compact :title="t('assets.noSchedule')" />
          <template v-else>
            <LineChart :points="points" :format="(n: number) => formatMoney(n)" />
            <div class="max-h-72 overflow-y-auto rounded-lg border">
              <table v-stack class="w-full text-sm">
                <thead class="text-muted-foreground bg-muted sticky top-0 border-b text-left text-xs">
                  <tr>
                    <th class="px-3 py-2 font-medium">{{ t("assets.month") }}</th>
                    <th class="px-3 py-2 text-right font-medium">{{ t("assets.depreciation") }}</th>
                    <th class="px-3 py-2 text-right font-medium">{{ t("assets.accumulated") }}</th>
                    <th class="px-3 py-2 text-right font-medium">{{ t("assets.bookValue") }}</th>
                    <th class="px-3 py-2 font-medium">{{ t("common.status") }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="r in rows" :key="r.month" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-1.5" :class="!r.posted && 'text-muted-foreground'">
                    <td class="whitespace-nowrap">{{ month(r.month) }}</td>
                    <td class="text-right tabular-nums">{{ formatMoney(r.amount) }}</td>
                    <td class="text-right tabular-nums">{{ formatMoney(r.accumulated) }}</td>
                    <td class="text-right tabular-nums">{{ formatMoney(r.book_value) }}</td>
                    <td class="text-xs">{{ r.posted ? t("assets.posted") : t("assets.projected") }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </template>
        </section>
      </div>
    </DialogContent>
  </Dialog>
</template>
