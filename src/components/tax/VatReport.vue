<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { BookOpen, FileDown, Landmark, RefreshCw, Undo2 } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { usePeriodOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { useServerError } from "@/composables/useServerError";
import { downloadRows } from "@/lib/csv";
import { formatDate, formatMoney, isoDate, round2 } from "@/lib/format";

const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();

const periods = usePeriodOptions();
const periodId = ref<number | null>(null);
watch(
  () => periods.rows.data.value,
  (rows) => {
    if (periodId.value == null && rows?.length) periodId.value = (rows.find((p) => String(p.end_date) < isoDate()) ?? rows[rows.length - 1]).id;
  },
  { immediate: true },
);
const periodLabel = computed(() => periods.options.value.find((o) => o.value === periodId.value)?.label ?? "");

const report = useRpcQuery("vat_report", () => (periodId.value ? { p_period_id: periodId.value } : null));
type Row = NonNullable<typeof report.data.value>[number];
const output = computed(() => (report.data.value ?? []).filter((r) => r.side === "output"));
const input = computed(() => (report.data.value ?? []).filter((r) => r.side === "input"));
const sum = (rows: Row[], k: "tax_base" | "vat") => round2(rows.reduce((s, r) => s + Number(r[k]), 0));
const net = computed(() => round2(sum(output.value, "vat") - sum(input.value, "vat")));
const sections = computed(() => [
  { key: "output", title: t("tax.vat.output"), rows: output.value },
  { key: "input", title: t("tax.vat.input"), rows: input.value },
]);

const settlements = useMasterRows("t_vat_settlements", { filter: () => ({ period_id: periodId.value }), enabled: () => !!periodId.value });
const settled = computed(() => settlements.data.value?.find((s) => s.status === "posted") ?? null);
const REFRESH = ["t_vat_settlements", "t_journals", "vat_report", "dashboard_summary", "cash_month_end"];
const settle = useRpcMutation("settle_vat", REFRESH);
const voidSettle = useRpcMutation("void_vat_settlement", REFRESH);
const confirming = ref<"settle" | "void" | null>(null);
async function confirm() {
  try {
    if (confirming.value === "settle") await settle.mutateAsync({ p_period_id: periodId.value! });
    else await voidSettle.mutateAsync({ p_id: settled.value!.id });
    toast.success(t(confirming.value === "settle" ? "tax.vat.settledOk" : "tax.vat.voidedOk"));
    confirming.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}

function docLink(r: Row) {
  if (r.doc_kind.startsWith("cash_")) return { path: "/cash", query: { tab: "txns", id: String(r.doc_id) } };
  return { path: r.doc_kind.startsWith("sales") ? "/sales/invoices" : "/purchases/bills", query: { id: String(r.doc_id) } };
}
const exportRows = () =>
  (report.data.value ?? []).map((r) => ({
    [t("tax.vat.side")]: t(`tax.vat.${r.side}`), [t("tax.docNo")]: r.doc_no, [t("common.date")]: r.doc_date, [t("common.partner")]: r.partner,
    NPWP: r.npwp, [t("tax.vat.fakturNo")]: r.tax_invoice_no, [t("tax.code")]: r.tax_code, DPP: r.tax_base, PPN: r.vat,
  }));
const coretax = () =>
  downloadRows(
    `coretax-ppn-keluaran-${periodLabel.value.replace(/\s+/g, "-").toLowerCase()}`,
    output.value.map((r) => ({
      "NPWP pembeli": r.npwp ?? "", Nama: r.partner ?? "", "Nomor faktur": r.tax_invoice_no ?? "",
      "Tanggal faktur": r.tax_invoice_date ?? r.doc_date, DPP: r.tax_base, PPN: r.vat, Referensi: r.doc_no,
    })),
  );
</script>

<template>
  <div class="space-y-4">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("tax.vat.title") }}</h2>
      <AppSelect v-model="periodId" :options="periods.options.value" :placeholder="t('tax.period')" class="w-40" :aria-label="t('tax.period')" />
      <Button variant="outline" size="sm" :disabled="!output.length" @click="coretax"><FileDown /> {{ t("tax.vat.coretax") }}</Button>
      <ExportMenu :name="`ppn-${periodLabel}`" :title="`${t('tax.vat.title')} ${periodLabel}`" :rows="exportRows" :disabled="!report.data.value?.length" />
    </div>

    <LoadingState v-if="report.isPending.value" />
    <EmptyState v-else-if="report.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="report.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <template v-else>
      <div class="bg-card grid gap-4 rounded-xl border p-4 sm:grid-cols-[1fr_auto] sm:items-center">
        <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4">
          <div><dt class="text-muted-foreground text-xs">{{ t("tax.vat.output") }}</dt><dd class="font-medium tabular-nums">{{ formatMoney(sum(output, "vat")) }}</dd></div>
          <div><dt class="text-muted-foreground text-xs">{{ t("tax.vat.input") }}</dt><dd class="font-medium tabular-nums">{{ formatMoney(sum(input, "vat")) }}</dd></div>
          <div>
            <dt class="text-muted-foreground text-xs">{{ net >= 0 ? t("tax.vat.underpaid") : t("tax.vat.overpaid") }}</dt>
            <dd class="font-semibold tabular-nums" :class="net > 0 ? 'text-rose-600' : 'text-success'">{{ formatMoney(Math.abs(net)) }}</dd>
          </div>
          <div>
            <dt class="text-muted-foreground text-xs">{{ t("tax.vat.settlement") }}</dt>
            <dd>
              <StatusBadge v-if="settled" tone="success">{{ t("tax.vat.settled") }}</StatusBadge>
              <StatusBadge v-else tone="muted">{{ t("tax.vat.notSettled") }}</StatusBadge>
            </dd>
          </div>
        </dl>
        <div class="flex flex-wrap gap-2">
          <template v-if="settled">
            <RouterLink v-slot="{ navigate }" :to="{ path: '/journals', query: { id: String(settled.journal_id) } }" custom>
              <Button variant="outline" size="sm" @click="navigate"><BookOpen /> {{ t("common.openJournal") }}</Button>
            </RouterLink>
            <Button v-if="can('tax', 'delete')" variant="ghost-destructive" size="sm" @click="confirming = 'void'"><Undo2 /> {{ t("tax.vat.voidSettlement") }}</Button>
          </template>
          <Button v-else-if="can('tax', 'update')" size="sm" class="active:scale-95" :disabled="!periodId" @click="confirming = 'settle'"><Landmark /> {{ t("tax.vat.settle") }}</Button>
        </div>
        <p v-if="settled" class="text-muted-foreground text-xs sm:col-span-2">
          {{ t("tax.vat.settledNote", { output: formatMoney(settled.output_vat), input: formatMoney(settled.input_vat), net: formatMoney(settled.net_vat) }) }}
        </p>
      </div>

      <section v-for="s in sections" :key="s.key" class="space-y-2">
        <h3 class="text-sm font-semibold">{{ s.title }} <span class="text-muted-foreground font-normal">({{ s.rows.length }})</span></h3>
        <EmptyState v-if="!s.rows.length" compact :title="t('common.empty')" />
        <div v-else class="bg-card overflow-x-auto rounded-xl border">
          <table v-stack class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr>
                <th class="px-3 py-2 font-medium">{{ t("tax.docNo") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.date") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("common.partner") }}</th>
                <th class="px-3 py-2 font-medium">NPWP</th>
                <th class="px-3 py-2 font-medium">{{ t("tax.vat.fakturNo") }}</th>
                <th class="px-3 py-2 font-medium">{{ t("tax.code") }}</th>
                <th class="px-3 py-2 text-right font-medium">DPP</th>
                <th class="px-3 py-2 text-right font-medium">PPN</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in s.rows" :key="`${r.doc_kind}-${r.doc_id}-${r.tax_code}`" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2">
                <td class="font-mono text-xs whitespace-nowrap">
                  <RouterLink :to="docLink(r)" class="text-primary-text hover:underline">{{ r.doc_no }}</RouterLink>
                </td>
                <td class="whitespace-nowrap">{{ formatDate(r.doc_date) }}</td>
                <td>{{ r.partner }}</td>
                <td class="font-mono text-xs">{{ r.npwp }}</td>
                <td class="font-mono text-xs">
                  <span v-if="r.tax_invoice_no">{{ r.tax_invoice_no }}</span>
                  <StatusBadge v-else tone="warning">{{ t("tax.vat.fakturMissing") }}</StatusBadge>
                </td>
                <td class="font-mono text-xs">{{ r.tax_code }}</td>
                <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(r.tax_base) }}</td>
                <td class="text-right whitespace-nowrap tabular-nums">{{ formatMoney(r.vat) }}</td>
              </tr>
            </tbody>
          </table>
          <p class="flex justify-end gap-6 border-t px-3 py-2 text-sm font-semibold tabular-nums">
            <span>DPP {{ formatMoney(sum(s.rows, "tax_base")) }}</span>
            <span>PPN {{ formatMoney(sum(s.rows, "vat")) }}</span>
          </p>
        </div>
      </section>
    </template>

    <ConfirmDialog
      :open="!!confirming"
      :title="confirming === 'void' ? t('tax.vat.voidTitle') : t('tax.vat.settleTitle', { period: periodLabel })"
      :description="confirming === 'void' ? t('tax.vat.voidBody') : t('tax.vat.settleBody')"
      :confirm-label="confirming === 'void' ? t('tax.vat.voidSettlement') : t('tax.vat.settle')"
      :busy="settle.isPending.value || voidSettle.isPending.value"
      :destructive="confirming === 'void'"
      @update:open="confirming = null"
      @confirm="confirm"
    />
  </div>
</template>
