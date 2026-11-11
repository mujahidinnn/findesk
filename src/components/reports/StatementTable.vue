<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { usePermissions } from "@/composables/usePermissions";
import { formatAmount } from "@/lib/format";
import type { Cell, ReportRow, RowKind } from "./reportRows";

defineProps<{ rows: ReportRow[]; columns: string[] }>();
const { t } = useI18n();
const { can } = usePermissions();
const ROW: Record<RowKind, string> = {
  section: "",
  group: "font-semibold",
  header: "text-muted-foreground",
  account: "",
  subtotal: "font-medium [&>td:not(:first-child)]:border-t",
  total: "font-semibold [&>td:not(:first-child)]:border-t",
  grand: "font-bold bg-secondary/50 [&>td]:border-t-2 [&>td]:border-foreground/30",
};
const fmt = (c: Cell | undefined) => (typeof c === "number" ? formatAmount(c) : (c ?? ""));
</script>

<template>
  <div class="overflow-x-auto">
    <table class="w-full text-sm tabular-nums">
      <thead class="text-muted-foreground bg-muted/60 border-b text-xs">
        <tr>
          <th class="px-3 py-2 text-left font-medium">{{ t("reports.account") }}</th>
          <th v-for="c in columns" :key="c" class="w-36 px-3 py-2 text-right font-medium whitespace-nowrap">{{ c }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="r in rows" :key="r.key" :class="ROW[r.kind]">
          <td v-if="r.kind === 'section'" :colspan="columns.length + 1" class="text-muted-foreground px-3 pt-5 pb-1 text-xs font-semibold tracking-wide uppercase">
            {{ r.label }}
          </td>
          <template v-else>
            <td class="py-1.5 pr-3" :style="{ paddingLeft: `${0.75 + (r.depth ?? 0) * 1}rem` }">
              <RouterLink v-if="r.accountId && can('journal', 'read')" :to="`/ledger?account=${r.accountId}`" class="hover:text-primary-text hover:underline">
                <span v-if="r.code" class="text-muted-foreground mr-2 font-mono text-xs">{{ r.code }}</span>{{ r.label }}
              </RouterLink>
              <template v-else><span v-if="r.code" class="text-muted-foreground mr-2 font-mono text-xs">{{ r.code }}</span>{{ r.label }}</template>
            </td>
            <td v-for="(c, i) in columns" :key="c" class="px-3 py-1.5 text-right whitespace-nowrap">{{ fmt(r.cells?.[i]) }}</td>
          </template>
        </tr>
      </tbody>
    </table>
  </div>
</template>
