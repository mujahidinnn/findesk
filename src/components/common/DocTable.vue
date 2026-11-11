<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { RefreshCw } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import AppSelect from "@/components/common/AppSelect.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import TablePager from "@/components/common/TablePager.vue";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { MasterRow } from "@/composables/useMasterRows";
import { rowText, usePaged } from "@/composables/usePaged";

const props = withDefaults(
  defineProps<{
    title: string;
    columns: string[];
    rows: MasterRow[];
    pending: boolean;
    failed: boolean;
    searchable?: boolean;
    statusLabel?: (status: string) => string;
    initialSearch?: string;
    initialStatus?: string;
  }>(),
  { searchable: true, statusLabel: undefined, initialSearch: undefined, initialStatus: undefined },
);
defineEmits<{ retry: [] }>();
const { t } = useI18n();

const search = ref(props.initialSearch ?? "");
const status = ref<string | null>(props.initialStatus || null);
watch(() => props.initialSearch, (v) => (search.value = v ?? ""));
watch(() => props.initialStatus, (v) => (status.value = v || null));
const statuses = computed(() => [
  ...new Set([...props.rows.map((r) => r.status), status.value].filter((s) => s != null).map(String)),
]);
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  return props.rows.filter((r) => (!q || rowText(r).includes(q)) && (!status.value || r.status === status.value));
});
const paged = usePaged(filtered);
</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ title }}</h2>
      <Input v-if="searchable" v-model="search" type="search" class="h-9 w-48" :placeholder="t('common.search')" :aria-label="t('common.search')" />
      <AppSelect
        v-if="statusLabel && (statuses.length > 1 || status)"
        v-model="status"
        :options="statuses.map((s) => ({ value: s, label: statusLabel!(s) }))"
        :null-label="t('common.allStatuses')"
        class="w-40"
        :aria-label="t('common.status')"
      />
      <slot name="toolbar" />
    </div>
    <LoadingState v-if="pending" :columns="columns.length" />
    <EmptyState v-else-if="failed" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="$emit('retry')"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!filtered.length" :title="t('common.empty')" />
    <template v-else>
      <div class="bg-card overflow-x-auto rounded-xl border">
        <table v-stack class="w-full text-sm">
          <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
            <tr>
              <th v-for="c in columns" :key="c" class="px-3 py-2 font-medium whitespace-nowrap">{{ c }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, i) in paged.rows.value" :key="row.id ?? i" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
              <slot name="row" :row="row" />
            </tr>
          </tbody>
        </table>
      </div>
      <TablePager v-model:page="paged.page.value" v-model:per-page="paged.perPage.value" :total="paged.total.value" :pages="paged.pages.value" />
    </template>
  </section>
</template>
