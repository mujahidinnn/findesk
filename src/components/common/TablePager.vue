<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronLeft, ChevronRight } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import { Button } from "@/components/ui/button";

const props = defineProps<{ total: number; pages: number }>();
const page = defineModel<number>("page", { required: true });
const perPage = defineModel<number>("perPage", { required: true });
const { t } = useI18n();
const from = computed(() => (!props.total ? 0 : page.value === 1 ? 1 : (page.value - 1) * perPage.value + 1));
const to = computed(() => Math.min(props.total, page.value * perPage.value));
const SIZES = [10, 25, 50, 100].map((n) => ({ value: n, label: String(n) })).concat({ value: Infinity, label: t("common.all") });
</script>

<template>
  <div v-if="total > 10" class="text-muted-foreground flex flex-wrap items-center justify-end gap-2 text-xs">
    <span>{{ t("common.perPage") }}</span>
    <AppSelect v-model="perPage" :options="SIZES" size="sm" class="w-20" :aria-label="t('common.perPage')" />
    <span class="tabular-nums">{{ t("common.range", { from: from.toLocaleString("id-ID"), to: to.toLocaleString("id-ID"), total: total.toLocaleString("id-ID") }) }}</span>
    <Button variant="ghost" size="icon" class="size-8" :disabled="page <= 1" :tooltip="t('common.prev')" @click="page--"><ChevronLeft /></Button>
    <Button variant="ghost" size="icon" class="size-8" :disabled="page >= pages" :tooltip="t('common.next')" @click="page++"><ChevronRight /></Button>
  </div>
</template>
