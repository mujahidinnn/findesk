<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import AppSelect from "@/components/common/AppSelect.vue";
import DocStatus from "@/components/common/DocStatus.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import { docLabel, openOf } from "@/components/invoice/docTypes";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useMasterRows } from "@/composables/useMasterRows";
import { useRpcQuery } from "@/composables/useRpcQuery";
import { formatAmount, formatDate, formatMoney, isoDate, yearStart } from "@/lib/format";

const id = defineModel<number | null>("id", { required: true });
const { t } = useI18n();

const query = useMasterRows("m_partners", { filter: () => ({ id: id.value }), columns: "*, term:m_payment_terms(name)", enabled: () => !!id.value });
const partner = computed(() => query.data.value?.[0] ?? null);
const docs = useMasterRows("t_invoices", {
  filter: () => ({ partner_id: id.value, status: "posted" }),
  columns: "id, doc_no, doc_type, invoice_date, due_date, currency, total, paid_amount, status",
  order: "due_date",
  enabled: () => !!id.value,
});
const exposure = useRpcQuery("partner_exposure", () => (id.value && partner.value?.is_customer ? { p_partner_id: id.value } : null));
const owed = useRpcQuery("partner_payable_exposure", () => (id.value && partner.value?.is_vendor ? { p_partner_id: id.value } : null));
const limit = computed(() => Number(partner.value?.credit_limit ?? 0));
const usedPct = computed(() => (limit.value > 0 ? Math.min(100, (Number(exposure.data.value ?? 0) / limit.value) * 100) : 0));

const side = ref<"receivable" | "payable">("receivable");
watch(partner, (p) => p && (side.value = p.is_customer ? "receivable" : "payable"));
const sideOptions = computed(() => [
  ...(partner.value?.is_customer ? [{ value: "receivable" as const, label: t("aging.receivable") }] : []),
  ...(partner.value?.is_vendor ? [{ value: "payable" as const, label: t("aging.payable") }] : []),
]);
const from = ref(yearStart());
const to = ref(isoDate());
const statement = useRpcQuery("partner_statement", () =>
  id.value && from.value && to.value ? { p_partner_id: id.value, p_side: side.value, p_from: from.value, p_to: to.value } : null,
);
const kind = (k: string) => (k === "opening" ? t("partners.opening") : t(`journalKinds.${k}`));
const docLink = (d: Record<string, unknown> & { id: number }) => `${String(d.doc_type).startsWith("sales") ? "/sales/invoices" : "/purchases/bills"}?id=${d.id}`;
const exportRows = () =>
  (statement.data.value ?? []).map((r) => ({
    [t("common.date")]: r.journal_date, [t("invoices.docNo")]: r.doc_no, [t("partners.kind")]: kind(r.kind), [t("common.description")]: r.memo,
    [t("common.debit")]: r.debit, [t("common.credit")]: r.credit, [t("common.balance")]: r.balance,
  }));
const open = computed({ get: () => !!id.value, set: (v) => { if (!v) id.value = null; } });
const info = computed(() => {
  const p = partner.value;
  if (!p) return [];
  return [
    [t("partners.npwp"), p.npwp], [t("partners.contact"), p.contact_person], [t("partners.phone"), p.phone], [t("partners.email"), p.email],
    [t("partners.address"), [p.address, p.city].filter(Boolean).join(", ")], [t("invoices.term"), (p.term as { name: string } | null)?.name],
    [t("common.currency"), p.currency], [t("partners.bank"), [p.bank_name, p.bank_account_no, p.bank_account_name].filter(Boolean).join(" · ")],
  ].filter(([, v]) => !!v) as [string, string][];
});
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle>{{ partner?.name }}</DialogTitle>
        <DialogDescription class="font-mono">{{ partner?.code }}</DialogDescription>
      </DialogHeader>
      <LoadingState v-if="query.isPending.value" variant="detail" />
      <EmptyState v-else-if="!partner" :title="t('common.loadFailed')" />
      <div v-else class="max-h-[74vh] space-y-5 overflow-y-auto">
        <div class="grid gap-4 lg:grid-cols-3">
          <dl class="bg-secondary/50 grid gap-x-6 gap-y-3 rounded-lg p-4 sm:grid-cols-2 lg:col-span-2">
            <div v-for="[label, value] in info" :key="label" class="min-w-0">
              <dt class="text-muted-foreground text-xs">{{ label }}</dt>
              <dd class="text-sm font-medium break-words">{{ value }}</dd>
            </div>
          </dl>
          <section v-if="partner.is_customer" class="bg-card space-y-2 rounded-xl border p-4">
            <h3 class="text-muted-foreground text-xs">{{ t("partners.exposure") }}</h3>
            <p class="text-xl font-semibold tabular-nums">{{ formatMoney(exposure.data.value ?? 0) }}</p>
            <template v-if="limit > 0">
              <div class="bg-secondary h-2 overflow-hidden rounded-full" role="meter" :aria-valuenow="usedPct" aria-valuemin="0" aria-valuemax="100">
                <div class="h-full rounded-full" :class="usedPct >= 100 ? 'bg-rose-500' : 'bg-primary'" :style="{ width: `${usedPct}%` }" />
              </div>
              <p class="text-muted-foreground text-xs">{{ t("partners.ofLimit", { limit: formatMoney(limit) }) }}</p>
            </template>
            <p v-else class="text-muted-foreground text-xs">{{ t("partners.noLimit") }}</p>
          </section>
          <section v-if="partner.is_vendor" class="bg-card space-y-2 rounded-xl border p-4">
            <h3 class="text-muted-foreground text-xs">{{ t("partners.owed") }}</h3>
            <p class="text-xl font-semibold tabular-nums">{{ formatMoney(owed.data.value ?? 0) }}</p>
          </section>
        </div>

        <section class="space-y-2">
          <h3 class="text-sm font-semibold">{{ t("partners.openDocs") }}</h3>
          <LoadingState v-if="docs.isPending.value" variant="list" :rows="2" />
          <EmptyState v-else-if="!docs.data.value?.length" :title="t('payments.noOpenDocs')" compact />
          <ul v-else class="divide-y rounded-lg border text-sm">
            <li v-for="d in docs.data.value" :key="d.id" class="flex flex-wrap items-center gap-3 px-3 py-2">
              <span class="min-w-0 flex-1">
                <RouterLink :to="docLink(d)" class="text-primary-text font-mono text-xs hover:underline">{{ docLabel(d) }}</RouterLink>
                <span class="text-muted-foreground block text-xs">{{ t(`invoices.kinds.${d.doc_type}`) }} · {{ t("invoices.dueDate") }} {{ formatDate(d.due_date as string) }}</span>
              </span>
              <DocStatus :status="String(d.status)" :paid="d.paid_amount" :total="d.total" :due="d.due_date as string" />
              <span class="font-medium tabular-nums">{{ formatMoney(openOf(d), String(d.currency)) }}</span>
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <div class="toolbar">
            <h2 class="mr-auto text-sm font-semibold">{{ t("partners.statement") }}</h2>
            <AppSelect v-if="sideOptions.length > 1" v-model="side" :options="sideOptions" class="w-36" :aria-label="t('partners.ledger')" />
            <PeriodFilter v-model:from="from" v-model:to="to" />
            <ExportMenu
              :name="`statement-${partner.code}`"
              :title="`${t('partners.statement')} · ${partner.name} · ${formatDate(from)} - ${formatDate(to)}`"
              :rows="exportRows"
              :disabled="!statement.data.value?.length"
            />
          </div>
          <LoadingState v-if="statement.isPending.value" :columns="6" :rows="4" />
          <EmptyState v-else-if="statement.isError.value" :title="t('common.loadFailed')" compact />
          <div v-else class="overflow-x-auto rounded-lg border">
            <table v-stack class="w-full text-sm">
              <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
                <tr class="[&>th]:px-3 [&>th]:py-2 [&>th]:font-medium">
                  <th>{{ t("common.date") }}</th>
                  <th>{{ t("invoices.docNo") }}</th>
                  <th>{{ t("common.description") }}</th>
                  <th class="text-right">{{ t("common.debit") }}</th>
                  <th class="text-right">{{ t("common.credit") }}</th>
                  <th class="text-right">{{ t("common.balance") }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(r, i) in statement.data.value" :key="i" class="border-b last:border-0 [&>td]:px-3 [&>td]:py-2" :class="r.kind === 'opening' && 'bg-secondary/40 font-medium'">
                  <td class="whitespace-nowrap">{{ formatDate(r.journal_date) }}</td>
                  <td class="font-mono text-xs">{{ r.doc_no ?? "" }}</td>
                  <td>
                    {{ r.memo }}
                    <span class="text-muted-foreground block text-xs">{{ kind(r.kind) }}</span>
                  </td>
                  <td class="text-right tabular-nums">{{ formatAmount(r.debit) }}</td>
                  <td class="text-right tabular-nums">{{ formatAmount(r.credit) }}</td>
                  <td class="text-right font-medium tabular-nums">{{ formatAmount(r.balance) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </DialogContent>
  </Dialog>
</template>
