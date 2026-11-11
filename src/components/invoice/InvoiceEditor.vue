<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { Paperclip, Save, Send } from "@lucide/vue";
import type { SupabaseClient } from "@supabase/supabase-js";
import AppSelect from "@/components/common/AppSelect.vue";
import SearchSelect from "@/components/common/SearchSelect.vue";
import InvoiceLineEditor from "@/components/invoice/InvoiceLineEditor.vue";
import { blankLine, docLabel, isNote, noteTarget, sideOf, type DocType, type InvoiceLine } from "@/components/invoice/docTypes";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useCurrencyOptions, usePartnerOptions, useSimpleOptions } from "@/composables/useLookups";
import { useMasterRows } from "@/composables/useMasterRows";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const db = supabase as unknown as SupabaseClient;
const props = defineProps<{ docType: DocType; id?: number | null }>();
const open = defineModel<boolean>("open", { required: true });
const emit = defineEmits<{ saved: [id: number] }>();
const { t } = useI18n();
const serverError = useServerError();

const side = computed(() => sideOf(props.docType));
const note = computed(() => isNote(props.docType));
const partners = usePartnerOptions(() => (side.value === "sales" ? "customer" : "vendor"));
const terms = useSimpleOptions("m_payment_terms");
const costCenters = useSimpleOptions("m_cost_centers");
const projects = useSimpleOptions("m_projects");
const currencies = useCurrencyOptions();

const blank = () => ({
  partner_id: null as number | null,
  invoice_date: isoDate(),
  due_date: null as string | null,
  term_id: null as number | null,
  currency: "IDR",
  fx_rate: 1 as number | null,
  reference: "",
  tax_invoice_no: "",
  tax_invoice_date: null as string | null,
  original_invoice_id: null as number | null,
  cost_center_id: null as number | null,
  project_id: null as number | null,
  note: "",
  attachment_path: null as string | null,
});
const form = ref(blank());
const lines = ref<InvoiceLine[]>([blankLine()]);
const loading = ref(false);
let hydrating = false;

watch(open, async (o) => {
  if (!o) return;
  hydrating = true;
  form.value = blank();
  lines.value = [blankLine()];
  if (props.id) {
    loading.value = true;
    try {
      const [h, l] = await Promise.all([
        db.from("t_invoices").select("*").eq("id", props.id).single(),
        db.from("t_invoice_lines").select("*").eq("invoice_id", props.id).order("line_no"),
      ]);
      if (h.error) throw h.error;
      if (l.error) throw l.error;
      const keys = Object.keys(blank()) as (keyof ReturnType<typeof blank>)[];
      form.value = Object.fromEntries(keys.map((k) => [k, h.data[k] ?? blank()[k]])) as ReturnType<typeof blank>;
      form.value.fx_rate = Number(h.data.fx_rate);
      lines.value = l.data.length
        ? l.data.map((r) => ({
            item_id: r.item_id, account_id: r.account_id, description: r.description ?? "", qty: Number(r.qty),
            unit_price: Number(r.unit_price), discount: Number(r.discount) || null, tax_id: r.tax_id, wht_tax_id: r.wht_tax_id,
          }))
        : [blankLine()];
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
  (id) => {
    if (hydrating) return;
    const p = partners.rows.data.value?.find((r) => r.id === id);
    form.value.original_invoice_id = null;
    if (!p) return;
    form.value.term_id = (p.term_id as number | null) ?? null;
    form.value.currency = String(p.currency ?? "IDR");
  },
);
watch(
  () => [form.value.currency, form.value.invoice_date] as const,
  async ([cur, date]) => {
    if (hydrating) return;
    if (cur === "IDR") return void (form.value.fx_rate = 1);
    const { data } = await supabase.rpc("fx_rate_on", { p_currency: cur, p_date: date });
    if (data) form.value.fx_rate = Number(data);
  },
);

const termDays = computed(() => Number(terms.rows.data.value?.find((r) => r.id === form.value.term_id)?.days ?? 0));
const autoDue = computed(() => {
  const d = new Date(`${form.value.invoice_date}T00:00`);
  d.setDate(d.getDate() + termDays.value);
  return isoDate(d);
});

const originals = useMasterRows("t_invoices", {
  filter: () => ({ partner_id: form.value.partner_id, doc_type: noteTarget(props.docType), currency: form.value.currency }),
  columns: "id, doc_no, invoice_date, total, paid_amount, status",
  order: "invoice_date",
  descending: true,
  enabled: () => open.value && note.value && !!form.value.partner_id,
});
const originalOptions = computed(() =>
  (originals.data.value ?? [])
    .filter((r) => r.status === "posted" || r.status === "paid")
    .map((r) => ({ value: r.id, label: `${docLabel(r)} · ${formatDate(String(r.invoice_date))} · ${formatMoney(r.total, form.value.currency)}` })),
);

const uploading = ref(false);
async function upload(e: Event) {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  uploading.value = true;
  try {
    const ext = file.name.split(".").pop()?.toLowerCase() || "pdf";
    const path = `invoices/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const { error } = await supabase.storage.from("attachments").upload(path, file, { contentType: file.type });
    if (error) throw error;
    form.value.attachment_path = path;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    uploading.value = false;
    input.value = "";
  }
}
async function viewAttachment() {
  if (!form.value.attachment_path) return;
  const { data, error } = await supabase.storage.from("attachments").createSignedUrl(form.value.attachment_path, 300);
  if (error) return void toast.error(serverError(error));
  window.open(data.signedUrl, "_blank", "noopener");
}

const saveDraft = useRpcMutation("save_invoice_draft", ["t_invoices", "t_invoice_lines"]);
const submit = useRpcMutation("submit_invoice", ["t_invoices"]);
const saving = ref(false);
const blankToNull = (v: string | null) => (v && v.trim() ? v.trim() : null);

async function save(post: boolean) {
  const f = form.value;
  const header = {
    partner_id: f.partner_id, invoice_date: f.invoice_date, due_date: f.due_date || null, term_id: f.term_id, currency: f.currency,
    fx_rate: f.currency === "IDR" ? 1 : f.fx_rate, reference: blankToNull(f.reference), tax_invoice_no: blankToNull(f.tax_invoice_no),
    tax_invoice_date: f.tax_invoice_date || null, original_invoice_id: note.value ? f.original_invoice_id : null,
    cost_center_id: f.cost_center_id, project_id: f.project_id, note: blankToNull(f.note), attachment_path: f.attachment_path,
  };
  const rows = lines.value.map((l, i) => ({
    line_no: i + 1, item_id: l.item_id, account_id: l.account_id, description: blankToNull(l.description), qty: l.qty,
    unit_price: l.unit_price ?? 0, discount: l.discount ?? 0, tax_id: l.tax_id, wht_tax_id: side.value === "purchase" ? l.wht_tax_id : null,
  }));
  saving.value = true;
  try {
    const id = await saveDraft.mutateAsync({
      p_id: props.id ?? undefined, p_header: props.id ? header : { ...header, doc_type: props.docType }, p_lines: rows,
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
const formId = computed(() => `invoice-form-${props.docType}`);
</script>

<template>
  <Dialog v-model:open="open">
    <DialogContent class="sm:max-w-5xl">
      <DialogHeader>
        <DialogTitle>{{ t(`invoices.kinds.${docType}`) }}</DialogTitle>
        <DialogDescription>{{ id ? t("invoices.editDraft") : t("invoices.newDraft") }}</DialogDescription>
      </DialogHeader>
      <form :id="formId" ref="formEl" class="max-h-[72vh] space-y-4 overflow-y-auto p-1" @submit.prevent="save(false)">
        <fieldset :disabled="loading" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-partner`">{{ t(side === "sales" ? "invoices.customer" : "invoices.vendor") }}</Label>
            <SearchSelect :id="`${formId}-partner`" v-model="form.partner_id" :options="partners.options.value" required />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-date`">{{ t("common.date") }}</Label>
            <input :id="`${formId}-date`" v-model="form.invoice_date" type="date" required :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-term`">{{ t("invoices.term") }}</Label>
            <AppSelect :id="`${formId}-term`" v-model="form.term_id" :options="terms.options.value" null-label="-" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-due`">{{ t("invoices.dueDate") }}</Label>
            <input :id="`${formId}-due`" v-model="form.due_date" type="date" :min="form.invoice_date" :class="FIELD_CLASS" />
            <p v-if="!form.due_date" class="text-muted-foreground text-[11px]">{{ t("invoices.dueAuto", { date: formatDate(autoDue) }) }}</p>
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-cur`">{{ t("common.currency") }}</Label>
            <AppSelect :id="`${formId}-cur`" v-model="form.currency" :options="currencies" required />
          </div>
          <div v-if="form.currency !== 'IDR'" class="space-y-1.5">
            <Label :for="`${formId}-rate`">{{ t("common.rate") }}</Label>
            <input :id="`${formId}-rate`" v-model.number="form.fx_rate" type="number" step="0.000001" min="0.000001" required :class="[FIELD_CLASS, 'text-right tabular-nums']" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-ref`">{{ t(side === "sales" ? "common.reference" : "invoices.vendorRef") }}</Label>
            <input :id="`${formId}-ref`" v-model="form.reference" :class="FIELD_CLASS" />
          </div>
          <div v-if="note" class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-orig`">{{ t("invoices.originalInvoice") }}</Label>
            <SearchSelect :id="`${formId}-orig`" v-model="form.original_invoice_id" :options="originalOptions" :null-label="t('invoices.noOriginal')" :disabled="!form.partner_id" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-fp`">{{ t("invoices.taxInvoiceNo") }}</Label>
            <input :id="`${formId}-fp`" v-model="form.tax_invoice_no" :class="[FIELD_CLASS, 'font-mono']" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-fpd`">{{ t("invoices.taxInvoiceDate") }}</Label>
            <input :id="`${formId}-fpd`" v-model="form.tax_invoice_date" type="date" :class="FIELD_CLASS" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-cc`">{{ t("common.costCenter") }}</Label>
            <AppSelect :id="`${formId}-cc`" v-model="form.cost_center_id" :options="costCenters.options.value" null-label="-" />
          </div>
          <div class="space-y-1.5">
            <Label :for="`${formId}-prj`">{{ t("common.project") }}</Label>
            <AppSelect :id="`${formId}-prj`" v-model="form.project_id" :options="projects.options.value" null-label="-" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-note`">{{ t("common.note") }}</Label>
            <input :id="`${formId}-note`" v-model="form.note" :class="FIELD_CLASS" />
          </div>
          <div v-if="side === 'purchase'" class="space-y-1.5 sm:col-span-2">
            <Label :for="`${formId}-file`">{{ t("invoices.attachment") }}</Label>
            <div class="flex items-center gap-2">
              <input
                :id="`${formId}-file`"
                type="file"
                accept="image/png,image/jpeg,image/webp,application/pdf"
                class="file:bg-secondary file:text-foreground min-w-0 flex-1 text-xs file:mr-3 file:rounded-md file:border-0 file:px-3 file:py-1.5 file:text-xs file:font-medium"
                :disabled="uploading"
                @change="upload"
              />
              <Button v-if="form.attachment_path" type="button" variant="outline" size="sm" @click="viewAttachment"><Paperclip /> {{ t("invoices.viewAttachment") }}</Button>
            </div>
          </div>
        </fieldset>
        <InvoiceLineEditor v-model="lines" :side="side" :currency="form.currency" />
      </form>
      <DialogFooter>
        <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
        <Button type="submit" variant="outline" :form="formId" :disabled="saving || uploading || loading" :loading="saving && !submit.isPending.value"><Save /> {{ t("invoices.saveDraft") }}</Button>
        <Button
          class="active:scale-95"
          :disabled="saving || uploading || loading"
          :loading="submit.isPending.value"
          @click="formEl?.reportValidity() && save(true)"
        >
          <Send /> {{ t("invoices.saveAndPost") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
