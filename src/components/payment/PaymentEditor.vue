<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { ListOrdered, Save, Send } from "@lucide/vue";
import type { SupabaseClient } from "@supabase/supabase-js";
import AppSelect from "@/components/common/AppSelect.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import AmountInput from "@/components/invoice/AmountInput.vue";
import { docLabel, openOf, PAYMENT_TARGETS, type Direction } from "@/components/invoice/docTypes";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useBankOptions, usePartnerOptions, useTaxOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, isoDate, round2 } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

export interface PaymentPreset { partnerId: number; invoiceId: number; currency: string }

const db = supabase as unknown as SupabaseClient;
const props = defineProps<{ direction: Direction; id?: number | null; preset?: PaymentPreset | null }>();
const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{ saved: [id: number] }>();
const { t } = useI18n();
const serverError = useServerError();

const partners = usePartnerOptions(() => (props.preset ? undefined : props.direction === "in" ? "customer" : "vendor"));
const banks = useBankOptions(() => props.preset?.currency);
const wht = useTaxOptions("wht");

const blank = () => ({
  partner_id: null as number | null,
  payment_date: isoDate(),
  bank_account_id: null as number | null,
  currency: "IDR",
  fx_rate: 1 as number | null,
  amount: null as number | null,
  wht_tax_id: null as number | null,
  wht_amount: null as number | null,
  wht_base: null as number | null,
  wht_slip_no: "",
  reference: "",
  note: "",
});
const form = ref(blank());
const alloc = ref<Record<number, number | null>>({});
const loading = ref(false);
let hydrating = false;
let prefillInvoice: number | null = null;

watch(open, async (o) => {
  if (!o) return;
  hydrating = true;
  form.value = blank();
  alloc.value = {};
  prefillInvoice = null;
  if (props.preset) {
    form.value.partner_id = props.preset.partnerId;
    form.value.currency = props.preset.currency;
    prefillInvoice = props.preset.invoiceId;
  }
  if (props.id) {
    loading.value = true;
    try {
      const [h, a] = await Promise.all([
        db.from("t_payments").select("*").eq("id", props.id).single(),
        db.from("t_payment_allocations").select("invoice_id, amount").eq("payment_id", props.id),
      ]);
      if (h.error) throw h.error;
      if (a.error) throw a.error;
      const keys = Object.keys(blank()) as (keyof ReturnType<typeof blank>)[];
      form.value = Object.fromEntries(keys.map((k) => [k, h.data[k] ?? blank()[k]])) as ReturnType<typeof blank>;
      for (const k of ["fx_rate", "amount", "wht_amount", "wht_base"] as const) form.value[k] = h.data[k] == null ? null : Number(h.data[k]) || null;
      alloc.value = Object.fromEntries(a.data.map((r) => [r.invoice_id, Number(r.amount)]));
    } catch (err) {
      toast.error(serverError(err));
      open.value = false;
    } finally {
      loading.value = false;
    }
  }
  setTimeout(() => (hydrating = false));
});

watch(
  () => form.value.partner_id,
  () => {
    if (!hydrating) alloc.value = {};
  },
);
watch(
  () => form.value.bank_account_id,
  (id) => {
    const bank = banks.rows.data.value?.find((b) => b.id === id);
    if (bank && !hydrating) {
      if (bank.currency !== form.value.currency) alloc.value = {};
      form.value.currency = String(bank.currency);
    }
  },
);
watch(
  () => [form.value.currency, form.value.payment_date] as const,
  async ([cur, date]) => {
    if (hydrating) return;
    if (cur === "IDR") return void (form.value.fx_rate = 1);
    const { data } = await supabase.rpc("fx_rate_on", { p_currency: cur, p_date: date });
    if (data) form.value.fx_rate = Number(data);
  },
);

const invoices = useMasterRows("t_invoices", {
  filter: () => ({ partner_id: form.value.partner_id, currency: form.value.currency, status: "posted" }),
  columns: "id, doc_no, doc_type, invoice_date, due_date, total, paid_amount",
  order: "due_date",
  enabled: () => open.value && !!form.value.partner_id,
});
const docs = computed(() => (invoices.data.value ?? []).filter((r) => PAYMENT_TARGETS[props.direction].includes(r.doc_type as never)));
watch(docs, (list) => {
  const inv = prefillInvoice ? list.find((r) => r.id === prefillInvoice) : null;
  if (!inv) return;
  alloc.value = { [inv.id]: openOf(inv) };
  if (!form.value.amount) form.value.amount = openOf(inv);
  prefillInvoice = null;
});

const isIn = computed(() => props.direction === "in");
const settle = computed(() => round2((form.value.amount ?? 0) + (isIn.value ? (form.value.wht_amount ?? 0) : 0)));
const allocated = computed(() => round2(Object.values(alloc.value).reduce<number>((s, v) => s + (v ?? 0), 0)));
const unallocated = computed(() => round2(settle.value - allocated.value));

function autoAllocate() {
  let pool = settle.value;
  const next: Record<number, number | null> = {};
  for (const d of docs.value) {
    const a = round2(Math.min(openOf(d), pool));
    next[d.id] = a > 0 ? a : null;
    pool = round2(pool - (a > 0 ? a : 0));
  }
  alloc.value = next;
}

const saveDraft = useRpcMutation("save_payment_draft", ["t_payments", "t_payment_allocations"]);
const submit = useRpcMutation("submit_payment", ["t_payments", "t_invoices"]);
const saving = ref(false);
const blankToNull = (v: string | null) => (v && v.trim() ? v.trim() : null);

async function save(post: boolean) {
  const f = form.value;
  const withheld = isIn.value && f.wht_tax_id && (f.wht_amount ?? 0) > 0;
  const header = {
    partner_id: f.partner_id, payment_date: f.payment_date, bank_account_id: f.bank_account_id, currency: f.currency,
    fx_rate: f.currency === "IDR" ? 1 : f.fx_rate, amount: f.amount, reference: blankToNull(f.reference), note: blankToNull(f.note),
    wht_tax_id: withheld ? f.wht_tax_id : null, wht_amount: withheld ? f.wht_amount : 0, wht_base: withheld ? f.wht_base : null, wht_slip_no: withheld ? blankToNull(f.wht_slip_no) : null,
  };
  const rows = Object.entries(alloc.value)
    .filter(([id, v]) => (v ?? 0) > 0 && docs.value.some((d) => d.id === Number(id)))
    .map(([invoice_id, amount]) => ({ invoice_id: Number(invoice_id), amount }));
  saving.value = true;
  try {
    const id = await saveDraft.mutateAsync({
      p_id: props.id ?? undefined, p_header: props.id ? header : { ...header, direction: props.direction }, p_lines: rows,
    });
    if (post) {
      const result = await submit.mutateAsync({ p_id: id });
      toast.success(t(result === "submitted" ? "invoices.submittedForApproval" : "invoices.postedOk"));
    } else {
      toast.success(t("common.saved"));
    }
    open.value = false;
    emit("saved", id);
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    saving.value = false;
  }
}
const formEl = ref<HTMLFormElement | null>(null);
const formId = computed(() => `payment-form-${props.direction}`);
const money = (v: unknown) => formatMoney(v, form.value.currency);
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-3xl">
      <DialogHeader>
        <DialogTitle>{{ t(`payments.kinds.${direction}`) }}</DialogTitle>
        <DialogDescription>{{ t(isIn ? "payments.inHint" : "payments.outHint") }}</DialogDescription>
      </DialogHeader>
      <form :id="formId" ref="formEl" class="max-h-[72vh] space-y-4 overflow-y-auto p-1" @submit.prevent="save(false)">
        <fieldset :disabled="loading" class="grid gap-3 sm:grid-cols-2">
          <div class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-partner`">{{ t(isIn ? "invoices.customer" : "invoices.vendor") }}</Label>
            <SearchSelect :id="`${formId}-partner`" v-model="form.partner_id" :options="partners.options.value" :disabled="!!preset" required />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-date`">{{ t("common.date") }}</Label>
            <input :id="`${formId}-date`" v-model="form.payment_date" type="date" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-bank`">{{ t("payments.bankAccount") }}</Label>
            <AppSelect :id="`${formId}-bank`" v-model="form.bank_account_id" :options="banks.options.value" required />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-amount`">{{ t(isIn ? "payments.amountReceived" : "payments.amountPaid") }} ({{ form.currency }})</Label>
            <AmountInput :id="`${formId}-amount`" v-model="form.amount" :currency="form.currency" required />
          </div>
          <div v-if="form.currency !== 'IDR'" class="space-y-1.5">
            <Label :for="`${formId}-rate`">{{ t("common.rate") }}</Label>
            <input :id="`${formId}-rate`" v-model.number="form.fx_rate" type="number" step="0.000001" min="0.000001" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
          </div>
          <template v-if="isIn">
            <div class="space-y-1.5">
              <Label :for="`${formId}-wht`">{{ t("payments.whtTax") }}</Label>
              <AppSelect :id="`${formId}-wht`" v-model="form.wht_tax_id" :options="wht.options.value" null-label="-" />
            </div>
            <div v-if="form.wht_tax_id" class="space-y-1.5">
              <Label :for="`${formId}-whta`">{{ t("payments.whtAmount") }}</Label>
              <AmountInput :id="`${formId}-whta`" v-model="form.wht_amount" :currency="form.currency" required />
            </div>
            <div v-if="form.wht_tax_id" class="space-y-1.5">
              <Label :for="`${formId}-whtb`">{{ t("payments.whtBase") }}</Label>
              <AmountInput :id="`${formId}-whtb`" v-model="form.wht_base" :currency="form.currency" />
            </div>
            <div v-if="form.wht_tax_id" class="space-y-1.5">
              <Label :for="`${formId}-slip`">{{ t("payments.whtSlipNo") }}</Label>
              <input :id="`${formId}-slip`" v-model="form.wht_slip_no" :class="[FIELD_CLASS, 'font-mono']" />
            </div>
          </template>
          <div class="space-y-1.5">
            <Label :for="`${formId}-ref`">{{ t("common.reference") }}</Label>
            <input :id="`${formId}-ref`" v-model="form.reference" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-note`">{{ t("common.note") }}</Label>
            <input :id="`${formId}-note`" v-model="form.note" :class="FIELD_CLASS" />
          </div>
        </fieldset>

        <section v-if="form.partner_id" class="space-y-2">
          <div class="flex items-center gap-2">
            <h3 class="mr-auto text-sm font-semibold">{{ t("payments.openDocs") }}</h3>
            <Button type="button" variant="outline" size="sm" :disabled="!docs.length || settle <= 0" @click="autoAllocate"><ListOrdered /> {{ t("payments.autoAllocate") }}</Button>
          </div>
          <EmptyState v-if="!docs.length" :title="t('payments.noOpenDocs')" compact />
          <div v-for="d in docs" :key="d.id" class="flex flex-wrap items-center gap-2 rounded-lg border px-3 py-2 text-sm">
            <span class="min-w-0 flex-1">
              <span class="font-mono text-xs">{{ docLabel(d) }}</span>
              <span class="text-muted-foreground block text-xs">
                {{ t(`invoices.kinds.${d.doc_type}`) }} · {{ t("invoices.dueDate") }} {{ formatDate(String(d.due_date)) }}
              </span>
            </span>
            <span class="text-muted-foreground text-xs tabular-nums">{{ t("invoices.open") }} {{ money(openOf(d)) }}</span>
            <AmountInput :model-value="alloc[d.id] ?? null" :currency="form.currency" :max="openOf(d)" class="w-40" :aria-label="docLabel(d)" @update:model-value="alloc[d.id] = $event" />
          </div>
          <dl class="ml-auto max-w-xs space-y-1 text-sm tabular-nums">
            <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("payments.toSettle") }}</dt><dd>{{ money(settle) }}</dd></div>
            <div class="flex justify-between gap-6"><dt class="text-muted-foreground">{{ t("payments.allocated") }}</dt><dd>{{ money(allocated) }}</dd></div>
            <div class="flex justify-between gap-6 border-t border-dashed pt-1 font-semibold" :class="unallocated < 0 && 'text-rose-600'">
              <dt>{{ t("payments.unallocated") }}</dt><dd>{{ money(unallocated) }}</dd>
            </div>
            <p v-if="unallocated > 0" class="text-muted-foreground text-[11px]">{{ t("payments.advanceHint") }}</p>
            <p v-else-if="unallocated < 0" class="text-[11px] text-rose-600">{{ t("serverErrors.OVER_ALLOCATED") }}</p>
          </dl>
        </section>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" variant="outline" :form="formId" :disabled="saving || loading || unallocated < 0" :loading="saving && !submit.isPending.value"><Save /> {{ t("invoices.saveDraft") }}</Button>
        <Button class="active:scale-95" :disabled="saving || loading || unallocated < 0" :loading="submit.isPending.value" @click="formEl?.reportValidity() && save(true)">
          <Send /> {{ t("invoices.saveAndPost") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
