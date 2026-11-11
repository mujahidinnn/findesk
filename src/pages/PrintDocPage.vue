<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useI18n } from "vue-i18n";
import { ArrowLeft, Printer } from "@lucide/vue";
import LoadingState from "@/components/common/LoadingState.vue";
import { featureOf, nameOf, sideOf } from "@/components/invoice/docTypes";
import { Button } from "@/components/ui/button";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";
import { usePermissions } from "@/composables/usePermissions";
import { useSettings } from "@/composables/useSettings";
import { formatDate, formatMoney, formatQty } from "@/lib/format";
import { terbilang } from "@/lib/terbilang";

const { t } = useI18n();
const route = useRoute();
const { can } = usePermissions();
const id = computed(() => Number(route.params.id));
const supported = computed(() => route.params.kind === "invoice");

const settings = useSettings();
const query = useMasterRows("t_invoices", {
  filter: () => ({ id: id.value }),
  columns: "*, partner:m_partners(code, name, npwp, address, city, phone, email)",
  enabled: () => supported.value && !!id.value,
});
const inv = computed(() => query.data.value?.[0] ?? null);
const lines = useMasterRows("t_invoice_lines", {
  filter: () => ({ invoice_id: id.value }),
  columns: "*, item:m_items(code, name, unit), tax:m_taxes!tax_id(name), wht:m_taxes!wht_tax_id(name)",
  order: "line_no",
  enabled: () => !!inv.value,
});
const docType = computed(() => String(inv.value?.doc_type ?? "sales_invoice"));
const allowed = computed(() => !!inv.value && (can(featureOf(docType.value)) || can("tax")));
const sales = computed(() => sideOf(docType.value) === "sales");
const currency = computed(() => String(inv.value?.currency ?? "IDR"));
const money = (v: unknown) => formatMoney(v, currency.value);
const banks = useMasterRows("m_bank_accounts", {
  filter: () => ({ kind: "bank", currency: currency.value, is_active: true }),
  order: "code",
  enabled: () => !!inv.value && sales.value && docType.value === "sales_invoice",
});
const partner = computed(() => (inv.value?.partner ?? null) as MasterRow | null);
const words = computed(() => (inv.value ? terbilang(Number(inv.value.total), currency.value === "IDR" ? "rupiah" : currency.value) : ""));
const whtNames = computed(() => [...new Set((lines.data.value ?? []).map((l) => nameOf(l.wht)).filter(Boolean))].join(", "));
const vatNames = computed(() => [...new Set((lines.data.value ?? []).map((l) => nameOf(l.tax)).filter(Boolean))].join(", "));
const print = () => window.print();
</script>

<template>
  <div class="min-h-screen bg-stone-100 py-6 text-stone-900 print:bg-white print:py-0">
    <div class="mx-auto mb-4 flex max-w-[210mm] justify-between px-4 print:hidden">
      <Button variant="outline" size="sm" @click="$router.back()"><ArrowLeft /> {{ t("print.back") }}</Button>
      <Button size="sm" :disabled="!allowed" @click="print"><Printer /> {{ t("common.print") }}</Button>
    </div>

    <LoadingState v-if="query.isPending.value && supported" variant="detail" class="mx-auto max-w-[210mm] px-4" />
    <p v-else-if="!supported || !inv" class="text-muted-foreground mx-auto max-w-[210mm] px-4 text-sm">{{ t("print.notFound") }}</p>
    <p v-else-if="!allowed" class="mx-auto max-w-[210mm] px-4 text-sm">{{ t("forbidden.body") }}</p>

    <article v-else class="mx-auto min-h-[297mm] max-w-[210mm] bg-white p-[14mm] text-[12px] leading-relaxed shadow-sm print:min-h-0 print:p-0 print:shadow-none">
      <header class="flex items-start justify-between gap-6 border-b-2 border-stone-800 pb-4">
        <div class="flex items-start gap-3">
          <img v-if="settings.data.value?.logo_url" :src="settings.data.value.logo_url" alt="" class="h-14 w-auto object-contain" />
          <div>
            <p class="text-base font-bold">{{ settings.data.value?.legal_name || settings.data.value?.company_name }}</p>
            <p class="whitespace-pre-line text-stone-600">{{ settings.data.value?.address }}</p>
            <p class="text-stone-600">
              <template v-if="settings.data.value?.phone">{{ settings.data.value.phone }}</template>
              <template v-if="settings.data.value?.email"> · {{ settings.data.value.email }}</template>
            </p>
            <p v-if="settings.data.value?.npwp" class="text-stone-600">NPWP {{ settings.data.value.npwp }}</p>
          </div>
        </div>
        <div class="text-right">
          <h1 class="text-xl font-bold tracking-wide uppercase">{{ t(`print.titles.${docType}`) }}</h1>
          <p class="font-mono">{{ inv.doc_no ?? `Draft #${inv.id}` }}</p>
          <p v-if="inv.status === 'void'" class="font-bold text-rose-700 uppercase">{{ t("status.void") }}</p>
        </div>
      </header>

      <section class="mt-5 grid grid-cols-2 gap-6">
        <div>
          <p class="text-[11px] text-stone-500 uppercase">{{ t(sales ? "print.billTo" : "print.from") }}</p>
          <p class="font-semibold">{{ partner?.name }}</p>
          <p class="whitespace-pre-line">{{ [partner?.address, partner?.city].filter(Boolean).join(", ") }}</p>
          <p v-if="partner?.npwp">NPWP {{ partner.npwp }}</p>
        </div>
        <dl class="grid grid-cols-[auto_1fr] gap-x-4 self-start text-right">
          <dt class="text-stone-500">{{ t("common.date") }}</dt><dd>{{ formatDate(String(inv.invoice_date)) }}</dd>
          <template v-if="inv.due_date"><dt class="text-stone-500">{{ t("invoices.dueDate") }}</dt><dd>{{ formatDate(String(inv.due_date)) }}</dd></template>
          <template v-if="inv.reference"><dt class="text-stone-500">{{ t("common.reference") }}</dt><dd>{{ inv.reference }}</dd></template>
          <template v-if="inv.tax_invoice_no"><dt class="text-stone-500">{{ t("invoices.taxInvoiceNo") }}</dt><dd class="font-mono">{{ inv.tax_invoice_no }}</dd></template>
          <template v-if="currency !== 'IDR'"><dt class="text-stone-500">{{ t("common.currency") }}</dt><dd>{{ currency }}</dd></template>
        </dl>
      </section>

      <table class="mt-6 w-full border-collapse">
        <thead>
          <tr class="border-y border-stone-800 text-left text-[11px] uppercase [&>th]:px-2 [&>th]:py-1.5">
            <th class="w-8">#</th>
            <th>{{ t("common.description") }}</th>
            <th class="text-right">{{ t("invoices.qty") }}</th>
            <th class="text-right">{{ t("invoices.unitPrice") }}</th>
            <th class="text-right">{{ t("invoices.discount") }}</th>
            <th class="text-right">{{ t("invoices.lineSubtotal") }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(l, i) in lines.data.value" :key="l.id" class="border-b border-stone-200 align-top [&>td]:px-2 [&>td]:py-1.5">
            <td>{{ i + 1 }}</td>
            <td>{{ l.description || nameOf(l.item) }}</td>
            <td class="text-right whitespace-nowrap tabular-nums">{{ formatQty(l.qty) }} {{ (l.item as MasterRow | null)?.unit ?? "" }}</td>
            <td class="text-right whitespace-nowrap tabular-nums">{{ money(l.unit_price) }}</td>
            <td class="text-right whitespace-nowrap tabular-nums">{{ Number(l.discount) ? money(l.discount) : "-" }}</td>
            <td class="text-right whitespace-nowrap tabular-nums">{{ money(l.line_subtotal) }}</td>
          </tr>
        </tbody>
      </table>

      <section class="mt-4 flex justify-end">
        <dl class="grid w-80 grid-cols-[1fr_auto] gap-x-6 gap-y-1 tabular-nums">
          <dt>{{ t("invoices.subtotal") }}</dt><dd class="text-right">{{ money(inv.subtotal) }}</dd>
          <template v-if="Number(inv.tax_total)"><dt>{{ vatNames || t("invoices.vat") }}</dt><dd class="text-right">{{ money(inv.tax_total) }}</dd></template>
          <template v-if="Number(inv.wht_total)"><dt>{{ whtNames || t("invoices.wht") }}</dt><dd class="text-right">({{ money(inv.wht_total) }})</dd></template>
          <dt class="border-t border-stone-800 pt-1 text-sm font-bold">{{ t("common.total") }}</dt>
          <dd class="border-t border-stone-800 pt-1 text-right text-sm font-bold">{{ money(inv.total) }}</dd>
        </dl>
      </section>
      <p class="mt-3 rounded border border-stone-300 px-3 py-2 italic"><span class="not-italic text-stone-500">{{ t("print.inWords") }}:</span> {{ words }}</p>

      <section v-if="banks.data.value?.length" class="mt-6">
        <p class="font-semibold">{{ t("print.paymentTo") }}</p>
        <ul>
          <li v-for="b in banks.data.value" :key="b.id">{{ b.bank_name || b.name }} · <span class="font-mono">{{ b.account_no }}</span><template v-if="b.account_holder"> · a.n. {{ b.account_holder }}</template></li>
        </ul>
        <p class="text-stone-500">{{ t("print.paymentRef", { no: inv.doc_no ?? "" }) }}</p>
      </section>
      <p v-if="inv.note" class="mt-4 whitespace-pre-line">{{ inv.note }}</p>

      <footer class="mt-10 grid grid-cols-2 gap-6">
        <p class="whitespace-pre-line text-stone-500">{{ settings.data.value?.invoice_footer }}</p>
        <div class="text-center">
          <p>{{ settings.data.value?.legal_name || settings.data.value?.company_name }}</p>
          <div class="h-20" />
          <p class="mx-auto w-48 border-t border-stone-800 pt-1 text-stone-500">{{ t("print.signature") }}</p>
        </div>
      </footer>
    </article>
  </div>
</template>

<style>
@media print {
  @page { size: A4; margin: 14mm; }
}
</style>
