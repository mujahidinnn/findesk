<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Play } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import DocTable from "@/components/common/DocTable.vue";
import { Button } from "@/components/ui/button";
import { usePeriodOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { formatMoney, isoDate } from "@/lib/format";

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const periods = usePeriodOptions();
const periodId = ref<number | null>(null);
watch(
  () => periods.rows.data.value,
  (rows) => {
    if (periodId.value == null && rows?.length) periodId.value = (rows.find((p) => String(p.start_date) <= isoDate()) ?? rows[0]).id;
  },
  { immediate: true },
);
const period = computed(() => periods.rows.data.value?.find((p) => p.id === periodId.value));

const posted = useMasterRows("t_asset_depreciation", {
  columns: "*, asset:t_assets(code, name)",
  filter: () => ({ period_id: periodId.value }),
  enabled: () => periodId.value != null,
});
const total = computed(() => (posted.data.value ?? []).reduce((s, r) => s + Number(r.amount), 0));
const assetOf = (v: unknown) => (v as { code?: string; name?: string } | null) ?? {};

const runDep = useRpcMutation("run_depreciation", ["t_asset_depreciation", "t_assets", "asset_register_summary", "asset_schedule", "t_journals"]);
async function run() {
  if (periodId.value == null) return;
  try {
    const res = (await runDep.mutateAsync({ p_period_id: periodId.value })) as { assets: number; total: number };
    if (res.assets) toast.success(t("assets.runDone", { n: res.assets, total: formatMoney(res.total) }));
    else toast.info(t("assets.runNothing"));
  } catch (err) {
    toast.error(serverError(err));
  }
}
</script>

<template>
  <DocTable
    :title="t('assets.depreciationOf', { period: periods.options.value.find((o) => o.value === periodId)?.label ?? '' })"
    :columns="[t('common.code'), t('common.name'), t('common.amount'), t('common.journal')]"
    :rows="posted.data.value ?? []"
    :pending="periodId != null && posted.isPending.value"
    :failed="posted.isError.value"
    :searchable="false"
    @retry="posted.refetch()"
  >
    <template #toolbar>
      <AppSelect v-model="periodId" :options="periods.options.value" class="w-40" :aria-label="t('assets.period')" />
      <span v-if="posted.data.value?.length" class="text-sm tabular-nums">{{ t("common.total") }}: <b>{{ formatMoney(total) }}</b></span>
      <Button
        v-if="can('asset', 'update')"
        size="sm"
        class="active:scale-95"
        :disabled="periodId == null || period?.status !== 'open' || runDep.isPending.value"
        :loading="runDep.isPending.value"
        @click="run"
      >
        <Play /> {{ t("assets.run") }}
      </Button>
    </template>
    <template #row="{ row }">
      <td class="font-mono text-xs">{{ assetOf(row.asset).code }}</td>
      <td>{{ assetOf(row.asset).name }}</td>
      <td class="text-right tabular-nums">{{ formatMoney(row.amount) }}</td>
      <td>
        <RouterLink v-if="can('journal', 'read')" :to="`/journals?id=${row.journal_id}`" class="text-primary-text hover:underline">
          {{ t("common.openJournal") }}
        </RouterLink>
      </td>
    </template>
  </DocTable>
</template>
