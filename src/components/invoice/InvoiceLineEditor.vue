<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Plus, X } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import AmountInput from "@/components/invoice/AmountInput.vue";
import { Button } from "@/components/ui/button";
import { useAccountOptions, useTaxOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { formatMoney, round2 } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";
import { blankLine, type InvoiceLine, type Side } from "@/components/invoice/docTypes";

const props = defineProps<{ side: Side; currency: string }>();
const lines = defineModel<InvoiceLine[]>({ required: true });
const { t } = useI18n();

const items = useMasterRows("m_items", { order: "code" });
const itemOptions = computed(() => (items.data.value ?? []).filter((i) => i.is_active).map((i) => ({ value: i.id, label: `${i.code} · ${i.name}` })));
const accounts = useAccountOptions(() =>
  props.side === "sales"
    ? { types: ["revenue"] }
    : { types: ["expense", "asset"], exclude: ["receivable", "bank", "cash", "accumulated_depreciation"] },
);
const vat = useTaxOptions("vat");
const wht = useTaxOptions("wht");
const taxOf = (rows: typeof vat.rows, id: number | null) => (id ? rows.data.value?.find((r) => r.id === id) : undefined);

function pickItem(line: InvoiceLine, id: number | null) {
  line.item_id = id;
  const it = items.data.value?.find((i) => i.id === id);
  if (!it) return;
  const sales = props.side === "sales";
  line.description = String(it.name);
  if (props.currency === "IDR") line.unit_price = Number(sales ? it.sales_price : it.purchase_price) || line.unit_price;
  line.tax_id = ((sales ? it.sales_tax_id : it.purchase_tax_id) as number | null) ?? null;
  if (!sales) line.wht_tax_id = (it.wht_tax_id as number | null) ?? null;
}

function preview(l: InvoiceLine) {
  const sub = round2((l.qty ?? 0) * (l.unit_price ?? 0) - (l.discount ?? 0));
  const v = taxOf(vat.rows, l.tax_id);
  const w = taxOf(wht.rows, l.wht_tax_id);
  const tax = v ? round2(round2(sub * Number(v.dpp_factor)) * Number(v.rate) / 100) : 0;
  const pph = w ? round2(sub * Number(w.rate) / 100) : 0;
  return { sub, tax, pph };
}
const totals = computed(() =>
  lines.value.map(preview).reduce((s, p) => ({ sub: s.sub + p.sub, tax: s.tax + p.tax, pph: s.pph + p.pph }), { sub: 0, tax: 0, pph: 0 }),
);
const money = (v: number) => formatMoney(round2(v), props.currency);
</script>

<template>
  <div class="space-y-2">
    <div v-for="(line, i) in lines" :key="i" class="space-y-2 rounded-lg border p-2">
      <div class="grid gap-2 sm:grid-cols-[1fr_1fr_1fr_2rem]">
        <SearchSelect :model-value="line.item_id" :options="itemOptions" :null-label="t('invoices.noItem')" :placeholder="t('invoices.item')" :aria-label="t('invoices.item')" @update:model-value="pickItem(line, $event)" />
        <SearchSelect
          v-model="line.account_id"
          :options="accounts.options.value"
          :null-label="line.item_id ? t('invoices.itemAccount') : undefined"
          :placeholder="t('common.account')"
          :required="!line.item_id"
          :aria-label="t('common.account')"
        />
        <input v-model="line.description" :class="FIELD_CLASS" :placeholder="t('common.description')" :aria-label="t('common.description')" />
        <Button type="button" variant="ghost" size="icon" class="size-8 max-sm:justify-self-end" :tooltip="t('common.delete')" :disabled="lines.length === 1" @click="lines.splice(i, 1)">
          <X />
        </Button>
      </div>
      <div class="grid grid-cols-2 gap-2" :class="side === 'purchase' ? 'sm:grid-cols-[5rem_1fr_1fr_1fr_1fr_8rem]' : 'sm:grid-cols-[5rem_1fr_1fr_1fr_8rem]'">
        <label class="min-w-0 space-y-1">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.qty") }}</span>
          <input v-model.number="line.qty" type="number" min="0.0001" step="any" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
        </label>
        <label class="min-w-0 space-y-1">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.unitPrice") }}</span>
          <AmountInput v-model="line.unit_price" :currency="currency" required />
        </label>
        <label class="min-w-0 space-y-1">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.discount") }}</span>
          <AmountInput v-model="line.discount" :currency="currency" />
        </label>
        <label class="min-w-0 space-y-1">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.vat") }}</span>
          <AppSelect v-model="line.tax_id" :options="vat.options.value" :null-label="t('invoices.noTax')" />
        </label>
        <label v-if="side === 'purchase'" class="min-w-0 space-y-1">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.wht") }}</span>
          <AppSelect v-model="line.wht_tax_id" :options="wht.options.value" :null-label="t('invoices.noTax')" />
        </label>
        <div class="min-w-0 space-y-1 text-right">
          <span class="text-muted-foreground block text-[11px]">{{ t("invoices.lineSubtotal") }}</span>
          <span class="block py-2 text-sm font-medium tabular-nums">{{ money(preview(line).sub) }}</span>
        </div>
      </div>
    </div>
    <div class="flex flex-wrap items-start justify-between gap-3">
      <Button type="button" variant="outline" size="sm" @click="lines.push(blankLine())"><Plus /> {{ t("common.addLine") }}</Button>
      <dl class="min-w-56 space-y-1 text-sm tabular-nums">
        <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.subtotal") }}</dt><dd>{{ money(totals.sub) }}</dd></div>
        <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.vat") }}</dt><dd>{{ money(totals.tax) }}</dd></div>
        <div v-if="side === 'purchase'" class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("invoices.wht") }}</dt><dd>({{ money(totals.pph) }})</dd></div>
        <div class="flex justify-between gap-6 border-t border-dashed pt-1 font-semibold"><dt>{{ t("common.total") }}</dt><dd>{{ money(totals.sub + totals.tax - totals.pph) }}</dd></div>
        <p class="text-muted-foreground text-[11px]">{{ t("invoices.previewHint") }}</p>
      </dl>
    </div>
  </div>
</template>
