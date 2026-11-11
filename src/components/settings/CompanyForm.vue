<script setup lang="ts">
import { ImagePlus, Save, X } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import AppSelect from "@/components/common/AppSelect.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { useSettings, useUpdateSettings } from "@/composables/useSettings";
import { supabase } from "@/integrations/supabase/client";
import type { Json } from "@/integrations/supabase/types";
import { FIELD_CLASS } from "@/lib/utils";

const { t, te } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();
const settings = useSettings();
const update = useUpdateSettings();
const canEdit = computed(() => can("settings", "update"));

const TEXT = ["company_name", "legal_name", "phone", "email", "npwp", "address", "invoice_footer"] as const;
type Form = Record<(typeof TEXT)[number] | "timezone", string> & {
  is_pkp: boolean; require_journal_approval: boolean; approval_threshold: number | null; logo_url: string | null;
};
const form = ref<Form>({
  company_name: "", legal_name: "", phone: "", email: "", npwp: "", address: "", invoice_footer: "", timezone: "Asia/Jakarta",
  is_pkp: true, require_journal_approval: true, approval_threshold: 0, logo_url: null,
});
const prefixes = ref<Record<string, string>>({});
watch(
  () => settings.data.value,
  (s) => {
    if (!s) return;
    form.value = {
      ...(Object.fromEntries(TEXT.map((k) => [k, s[k] ?? ""])) as Record<(typeof TEXT)[number], string>),
      timezone: s.timezone, is_pkp: s.is_pkp, require_journal_approval: s.require_journal_approval,
      approval_threshold: Number(s.approval_threshold), logo_url: s.logo_url,
    };
    prefixes.value = { ...(s.doc_prefixes as Record<string, string>) };
  },
  { immediate: true },
);
const ZONES = ["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura"];
const zoneOptions = computed(() =>
  [...new Set([...ZONES, form.value.timezone])].map((z) => ({ value: z, label: te(`settings.zones.${z}`) ? t(`settings.zones.${z}`) : z })),
);

const uploading = ref(false);
async function uploadLogo(e: Event) {
  const input = e.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  uploading.value = true;
  try {
    const path = `logo/${Date.now()}.${file.name.split(".").pop()?.toLowerCase() || "png"}`;
    const { error } = await supabase.storage.from("branding").upload(path, file, { contentType: file.type });
    if (error) throw error;
    form.value.logo_url = supabase.storage.from("branding").getPublicUrl(path).data.publicUrl;
  } catch (err) {
    toast.error(serverError(err));
  } finally {
    uploading.value = false;
    input.value = "";
  }
}

async function submit() {
  const f = form.value;
  try {
    await update.mutateAsync({
      ...Object.fromEntries(TEXT.map((k) => [k, f[k].trim() || null])),
      company_name: f.company_name.trim(),
      timezone: f.timezone,
      is_pkp: f.is_pkp,
      require_journal_approval: f.require_journal_approval,
      approval_threshold: f.approval_threshold ?? 0,
      logo_url: f.logo_url,
      doc_prefixes: Object.fromEntries(Object.entries(prefixes.value).map(([k, v]) => [k, v.trim().toUpperCase()])) as Json,
    });
    toast.success(t("common.saved"));
  } catch (err) {
    toast.error(serverError(err));
  }
}
</script>

<template>
  <LoadingState v-if="settings.isPending.value" variant="form" />
  <form v-else class="grid items-start gap-5 lg:grid-cols-2" @submit.prevent="submit">
    <fieldset class="contents" :disabled="!canEdit">
      <section class="bg-card space-y-4 rounded-xl border p-5 lg:row-span-3">
        <h2 class="font-semibold">{{ t("settings.company.identity") }}</h2>
        <div class="flex items-center gap-3">
          <img v-if="form.logo_url" :src="form.logo_url" alt="" class="size-14 shrink-0 rounded-lg border object-contain" />
          <span v-else class="bg-secondary flex size-14 shrink-0 items-center justify-center rounded-lg"><ImagePlus class="text-muted-foreground size-5" /></span>
          <div class="min-w-0 flex-1 space-y-1.5">
            <Label for="company-logo">{{ t("settings.company.logo") }}</Label>
            <input
              id="company-logo"
              type="file"
              accept="image/png,image/jpeg,image/webp"
              class="file:bg-secondary file:text-foreground w-full text-xs file:mr-3 file:rounded-md file:border-0 file:px-3 file:py-1.5 file:text-xs file:font-medium"
              :disabled="uploading"
              @change="uploadLogo"
            />
          </div>
          <Button v-if="form.logo_url" type="button" variant="ghost" size="icon" class="size-8" :tooltip="t('common.delete')" @click="form.logo_url = null"><X /></Button>
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-1.5">
            <Label for="company-name">{{ t("settings.company.name") }}</Label>
            <Input id="company-name" v-model="form.company_name" maxlength="120" required />
          </div>
          <div class="space-y-1.5">
            <Label for="company-legal">{{ t("settings.company.legalName") }}</Label>
            <Input id="company-legal" v-model="form.legal_name" maxlength="160" :placeholder="t('settings.company.legalNameHint')" />
          </div>
          <div class="space-y-1.5 sm:col-span-2">
            <Label for="company-address">{{ t("settings.company.address") }}</Label>
            <textarea id="company-address" v-model="form.address" :class="[FIELD_CLASS, 'h-20 py-2']" maxlength="500" />
          </div>
          <div class="space-y-1.5">
            <Label for="company-phone">{{ t("settings.company.phone") }}</Label>
            <Input id="company-phone" v-model="form.phone" type="tel" inputmode="tel" maxlength="32" />
          </div>
          <div class="space-y-1.5">
            <Label for="company-email">{{ t("settings.company.email") }}</Label>
            <Input id="company-email" v-model="form.email" type="email" maxlength="120" />
          </div>
          <div class="space-y-1.5">
            <Label for="company-tz">{{ t("settings.company.timezone") }}</Label>
            <AppSelect id="company-tz" :model-value="form.timezone" :options="zoneOptions" required @update:model-value="form.timezone = $event ?? 'Asia/Jakarta'" />
          </div>
        </div>
      </section>

      <section class="bg-card space-y-4 rounded-xl border p-5">
        <h2 class="font-semibold">{{ t("settings.company.tax") }}</h2>
        <div class="grid gap-4 sm:grid-cols-2">
          <div class="space-y-1.5">
            <Label for="company-npwp">NPWP</Label>
            <Input id="company-npwp" v-model="form.npwp" class="font-mono" maxlength="32" placeholder="00.000.000.0-000.000" />
          </div>
          <label class="flex items-start gap-2 text-sm sm:mt-7">
            <input v-model="form.is_pkp" type="checkbox" class="accent-primary mt-0.5 size-4" />
            <span>{{ t("settings.company.isPkp") }}<span class="text-muted-foreground block text-xs">{{ t("settings.company.isPkpHint") }}</span></span>
          </label>
        </div>
      </section>

      <section class="bg-card space-y-4 rounded-xl border p-5">
        <h2 class="font-semibold">{{ t("settings.company.approval") }}</h2>
        <label class="flex items-start gap-2 text-sm">
          <input v-model="form.require_journal_approval" type="checkbox" class="accent-primary mt-0.5 size-4" />
          <span>{{ t("settings.company.requireJournalApproval") }}<span class="text-muted-foreground block text-xs">{{ t("settings.company.requireJournalApprovalHint") }}</span></span>
        </label>
        <div class="max-w-xs space-y-1.5">
          <Label for="company-threshold">{{ t("settings.company.approvalThreshold") }}</Label>
          <MoneyInput id="company-threshold" :model-value="form.approval_threshold" required @update:model-value="form.approval_threshold = $event" />
          <p class="text-muted-foreground text-xs">{{ t("settings.company.approvalThresholdHint") }}</p>
        </div>
      </section>

      <section class="bg-card space-y-4 rounded-xl border p-5">
        <h2 class="font-semibold">{{ t("settings.company.documents") }}</h2>
        <div class="space-y-1.5">
          <Label for="company-footer">{{ t("settings.company.invoiceFooter") }}</Label>
          <textarea id="company-footer" v-model="form.invoice_footer" :class="[FIELD_CLASS, 'h-20 py-2']" maxlength="500" :placeholder="t('settings.company.invoiceFooterHint')" />
        </div>
        <div>
          <p class="text-sm font-medium">{{ t("settings.company.prefixes") }}</p>
          <p class="text-muted-foreground text-xs">{{ t("settings.company.prefixesHint") }}</p>
        </div>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div v-for="(_, k) in prefixes" :key="k" class="space-y-1.5">
            <Label :for="`prefix-${k}`" class="text-xs">{{ te(`settings.prefixKinds.${k}`) ? t(`settings.prefixKinds.${k}`) : k }}</Label>
            <Input :id="`prefix-${k}`" v-model="prefixes[k]" class="font-mono uppercase" pattern="[A-Za-z0-9\-]{1,10}" maxlength="10" required />
          </div>
        </div>
      </section>

      <Button v-if="canEdit" type="submit" class="w-fit active:scale-95 lg:col-span-2" :disabled="update.isPending.value || uploading" :loading="update.isPending.value"><Save /> {{ t("common.save") }}</Button>
    </fieldset>
  </form>
</template>
