<script setup lang="ts">
import { Download } from "@lucide/vue";
import { useI18n } from "vue-i18n";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { downloadRows, type ExportFormat } from "@/lib/csv";

const props = defineProps<{ name: string; title: string; rows: () => Record<string, unknown>[]; disabled?: boolean }>();
const { t } = useI18n();
const FORMATS: ExportFormat[] = ["xls", "csv", "pdf"];
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <Button variant="outline" size="sm" :disabled="disabled"><Download /> {{ t("common.export") }}</Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end">
      <DropdownMenuItem v-for="f in FORMATS" :key="f" @select="downloadRows(props.name, props.rows(), f, props.title)">{{ t(`export.${f}`) }}</DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
