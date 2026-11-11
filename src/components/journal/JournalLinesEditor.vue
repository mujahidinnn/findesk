<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Plus, Trash2 } from "@lucide/vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import { Button } from "@/components/ui/button";
import { useAccountOptions, useSimpleOptions } from "@/composables/useLookups";
import { formatMoney } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { blankLine, lineTotals, type JournalLine } from "./lines";

const lines = defineModel<JournalLine[]>({ required: true });
const { t } = useI18n();
const { options: accounts } = useAccountOptions({ exclude: ["receivable", "payable"] });
const { options: costCenters } = useSimpleOptions("m_cost_centers");
const { options: projects } = useSimpleOptions("m_projects");
const totals = computed(() => lineTotals(lines.value));

function setAmount(line: JournalLine, side: "debit" | "credit", e: Event) {
  const v = Number((e.target as HTMLInputElement).value);
  line[side] = v > 0 ? v : null;
  if (v > 0) line[side === "debit" ? "credit" : "debit"] = null;
}
const num = "text-right tabular-nums";
</script>

<template>
  <div class="space-y-2">
    <div class="overflow-x-auto rounded-lg border">
      <table v-stack class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr>
            <th class="min-w-56 px-2 py-2 font-medium">{{ t("common.account") }}</th>
            <th class="min-w-40 px-2 py-2 font-medium">{{ t("journals.memo") }}</th>
            <th class="w-36 px-2 py-2 text-right font-medium">{{ t("common.debit") }}</th>
            <th class="w-36 px-2 py-2 text-right font-medium">{{ t("common.credit") }}</th>
            <th class="min-w-36 px-2 py-2 font-medium">{{ t("common.costCenter") }}</th>
            <th class="min-w-36 px-2 py-2 font-medium">{{ t("common.project") }}</th>
            <th class="w-px px-2 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(l, i) in lines" :key="i" class="border-b last:border-0 [&>td]:px-2 [&>td]:py-1.5">
            <td>
              <SearchSelect v-model="l.account_id" :options="accounts" :required="!!(l.debit || l.credit)" :aria-label="t('common.account')" />
            </td>
            <td><input v-model="l.memo" :class="FIELD_CLASS" :aria-label="t('journals.memo')" /></td>
            <td>
              <input
                :value="l.debit ?? ''" type="number" step="0.01" min="0" inputmode="decimal" :class="[FIELD_CLASS, num]"
                :aria-label="t('common.debit')" @input="setAmount(l, 'debit', $event)"
              />
            </td>
            <td>
              <input
                :value="l.credit ?? ''" type="number" step="0.01" min="0" inputmode="decimal" :class="[FIELD_CLASS, num]"
                :aria-label="t('common.credit')" @input="setAmount(l, 'credit', $event)"
              />
            </td>
            <td><SearchSelect v-model="l.cost_center_id" :options="costCenters" :null-label="t('common.none')" :aria-label="t('common.costCenter')" /></td>
            <td><SearchSelect v-model="l.project_id" :options="projects" :null-label="t('common.none')" :aria-label="t('common.project')" /></td>
            <td>
              <Button
                type="button" variant="ghost-destructive" size="icon" class="size-8" :tooltip="t('common.delete')"
                :disabled="lines.length <= 2" @click="lines.splice(i, 1)"
              >
                <Trash2 />
              </Button>
            </td>
          </tr>
        </tbody>
        <tfoot class="border-t text-sm font-semibold">
          <tr class="[&>td]:px-2 [&>td]:py-2">
            <td colspan="2">{{ t("common.total") }}</td>
            <td :class="num">{{ formatMoney(totals.debit) }}</td>
            <td :class="num">{{ formatMoney(totals.credit) }}</td>
            <td colspan="3" />
          </tr>
        </tfoot>
      </table>
    </div>
    <div class="flex flex-wrap items-center gap-3">
      <Button type="button" variant="outline" size="sm" @click="lines.push(blankLine())"><Plus /> {{ t("common.addLine") }}</Button>
      <p class="text-muted-foreground mr-auto text-xs">{{ t("journals.lineHint") }} {{ t("journals.controlNote") }}</p>
      <span
        role="status"
        :class="[
          'rounded-lg px-3 py-1.5 text-sm font-semibold tabular-nums',
          totals.diff === 0 ? 'bg-green-500/15 text-green-700 dark:text-green-400' : 'bg-rose-500/10 text-rose-700 dark:text-rose-400',
        ]"
      >
        {{ totals.diff === 0 ? t("journals.balanced") : `${t("journals.difference")} ${formatMoney(Math.abs(totals.diff))} (${totals.diff > 0 ? t("common.debit") : t("common.credit")})` }}
      </span>
    </div>
  </div>
</template>
