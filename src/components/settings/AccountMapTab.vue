<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { useMutation, useQueryClient } from "@tanstack/vue-query";
import { RefreshCw } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import { Button } from "@/components/ui/button";
import { useMasterRows } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";

const KEYS: { key: string; types: string[]; subtypes?: string[] }[] = [
  { key: "receivable", types: ["asset"], subtypes: ["receivable"] },
  { key: "payable", types: ["liability"], subtypes: ["payable"] },
  { key: "vat_payable", types: ["liability"] },
  { key: "vat_overpaid", types: ["asset"] },
  { key: "employee_payable", types: ["liability"] },
  { key: "retained_earnings", types: ["equity"] },
  { key: "opening_equity", types: ["equity"] },
  { key: "fx_gain", types: ["revenue"] },
  { key: "fx_loss", types: ["expense"] },
  { key: "rounding", types: ["expense", "revenue"] },
  { key: "bank_fee", types: ["expense"] },
  { key: "asset_gain", types: ["revenue"] },
  { key: "asset_loss", types: ["expense"] },
  { key: "sales_revenue", types: ["revenue"] },
  { key: "purchase_expense", types: ["expense", "asset"] },
];

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();
const qc = useQueryClient();
const map = useMasterRows("m_account_map", { order: "key" });
const accounts = useMasterRows("m_accounts", { order: "code" });
const current = computed(() => new Map((map.data.value ?? []).map((r) => [String(r.key), Number(r.account_id)])));
const optionsFor = (k: (typeof KEYS)[number]) =>
  (accounts.data.value ?? [])
    .filter((a) => a.is_postable && a.is_active && k.types.includes(String(a.account_type)) && (!k.subtypes || k.subtypes.includes(String(a.subtype))))
    .map((a) => ({ value: a.id, label: `${a.code} · ${a.name}` }));

const save = useMutation({
  mutationFn: async (v: { key: string; account_id: number }) => {
    const { error } = await supabase.from("m_account_map").upsert(v);
    if (error) throw error;
  },
  onSuccess: () => qc.invalidateQueries({ queryKey: ["m_account_map"] }),
});
async function pick(key: string, accountId: number | null) {
  if (accountId == null || accountId === current.value.get(key)) return;
  try {
    await save.mutateAsync({ key, account_id: accountId });
    toast.success(t("common.saved"));
  } catch (e) {
    toast.error(serverError(e));
  }
}
</script>

<template>
  <section class="space-y-3">
    <div>
      <h2 class="font-semibold">{{ t("settings.accountMap.title") }}</h2>
      <p class="text-muted-foreground text-sm">{{ t("settings.accountMap.intro") }}</p>
    </div>
    <LoadingState v-if="map.isPending.value || accounts.isPending.value" :columns="2" :rows="8" />
    <EmptyState v-else-if="map.isError.value || accounts.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="(map.refetch(), accounts.refetch())"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <div v-else class="bg-card divide-y divide-dashed rounded-xl border">
      <div v-for="k in KEYS" :key="k.key" class="grid gap-2 px-4 py-3 md:grid-cols-[minmax(0,1fr)_minmax(0,22rem)] md:items-center">
        <div class="min-w-0">
          <p class="text-sm font-medium">{{ t(`settings.accountMap.keys.${k.key}.label`) }} <span class="text-muted-foreground font-mono text-[11px]">{{ k.key }}</span></p>
          <p class="text-muted-foreground text-xs">{{ t(`settings.accountMap.keys.${k.key}.body`) }}</p>
        </div>
        <SearchSelect
          :model-value="current.get(k.key) ?? null"
          :options="optionsFor(k)"
          :disabled="!can('settings', 'update') || save.isPending.value"
          :aria-label="t(`settings.accountMap.keys.${k.key}.label`)"
          :class="!current.has(k.key) && 'border-rose-400'"
          @update:model-value="pick(k.key, $event)"
        />
      </div>
    </div>
  </section>
</template>
