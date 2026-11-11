<script setup lang="ts">
import { Printer, RefreshCw } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { Button } from "@/components/ui/button";
import { useSettings } from "@/composables/useSettings";

defineProps<{ title: string; period: string; exportName: string; rows: () => Record<string, unknown>[]; pending: boolean; failed: boolean }>();
defineEmits<{ retry: [] }>();
const { t } = useI18n();
const settings = useSettings();
const print = () => window.print();
</script>

<template>
  <section class="space-y-4">
    <div class="toolbar print:hidden">
      <slot name="controls" />
      <div class="ml-auto flex gap-2">
        <ExportMenu :name="exportName" :title="`${title} ${period}`" :rows="rows" :disabled="pending || failed" />
        <Button variant="outline" size="sm" :disabled="pending || failed" @click="print"><Printer /> {{ t("common.print") }}</Button>
      </div>
    </div>
    <LoadingState v-if="pending" :rows="10" :columns="3" />
    <EmptyState v-else-if="failed" class="bg-card rounded-xl border" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="$emit('retry')"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <article v-else class="report-print-area bg-card rounded-xl border p-4 sm:p-6 print:rounded-none print:border-0 print:p-0">
      <header class="mb-4 text-center">
        <p class="text-muted-foreground text-xs font-semibold tracking-wide uppercase">{{ settings.data.value?.legal_name || settings.data.value?.company_name }}</p>
        <h2 class="mt-1 text-lg font-bold">{{ title }}</h2>
        <p class="text-muted-foreground text-xs">{{ period }}</p>
      </header>
      <slot />
    </article>
  </section>
</template>
