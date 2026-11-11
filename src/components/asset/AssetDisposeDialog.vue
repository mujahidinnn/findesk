<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { PackageMinus } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import MoneyInput from "@/components/common/MoneyInput.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { useBankOptions } from "@/composables/useLookups";
import type { MasterRow } from "@/composables/useMasterRows";
import { useRpcMutation } from "@/composables/useRpcMutation";
import { useServerError } from "@/composables/useServerError";
import { formatMoney, isoDate } from "@/lib/format";
import { FIELD_CLASS } from "@/lib/utils";

const asset = defineModel<MasterRow | null>("asset", { required: true });
const props = defineProps<{ bookValue: number }>();
const { t } = useI18n();
const serverError = useServerError();
const banks = useBankOptions("IDR");
const dispose = useRpcMutation("dispose_asset", ["t_assets", "t_asset_depreciation", "asset_register_summary", "asset_schedule", "t_journals"]);

const form = ref({ date: isoDate(), proceeds: 0 as number | null, bank_id: null as number | null, note: "" });
watch(asset, (a) => a && (form.value = { date: isoDate(), proceeds: 0, bank_id: null, note: "" }));
const gain = computed(() => (form.value.proceeds ?? 0) - props.bookValue);

async function submit() {
  if (!asset.value) return;
  try {
    await dispose.mutateAsync({
      p_id: asset.value.id,
      p_date: form.value.date,
      p_proceeds: form.value.proceeds ?? 0,
      p_bank_id: form.value.proceeds ? (form.value.bank_id ?? undefined) : undefined,
      p_note: form.value.note.trim() || undefined,
    });
    toast.success(t("common.saved"));
    asset.value = null;
  } catch (err) {
    toast.error(serverError(err));
  }
}
</script>

<template>
  <Dialog :open="!!asset" @update:open="(v) => !v && (asset = null)">
    <DialogContent class="sm:max-w-md">
      <DialogHeader>
        <DialogTitle>{{ t("assets.dispose") }}</DialogTitle>
        <DialogDescription>{{ asset?.code }} · {{ asset?.name }}</DialogDescription>
      </DialogHeader>
      <form id="dispose-form" class="space-y-3" @submit.prevent="submit">
        <div class="grid grid-cols-2 gap-3">
          <div class="space-y-1.5">
            <Label for="dsp-date">{{ t("assets.disposalDate") }}</Label>
            <input id="dsp-date" v-model="form.date" type="date" :class="FIELD_CLASS" required />
          </div>
          <div class="space-y-1.5">
            <Label for="dsp-proceeds">{{ t("assets.proceeds") }}</Label>
            <MoneyInput id="dsp-proceeds" v-model="form.proceeds" />
          </div>
        </div>
        <div v-if="form.proceeds" class="space-y-1.5">
          <Label for="dsp-bank">{{ t("assets.receivedIn") }}</Label>
          <AppSelect id="dsp-bank" v-model="form.bank_id" :options="banks.options.value" :placeholder="t('common.pick')" required />
        </div>
        <div class="space-y-1.5">
          <Label for="dsp-note">{{ t("common.note") }}</Label>
          <textarea id="dsp-note" v-model="form.note" :class="[FIELD_CLASS, 'h-16 py-2']" />
        </div>
        <dl class="bg-secondary/50 space-y-1 rounded-lg p-3 text-sm">
          <div class="flex justify-between"><dt class="text-muted-foreground">{{ t("assets.bookValue") }}</dt><dd class="tabular-nums">{{ formatMoney(bookValue) }}</dd></div>
          <div class="flex justify-between font-medium">
            <dt>{{ gain >= 0 ? t("assets.gain") : t("assets.loss") }}</dt>
            <dd :class="['tabular-nums', gain < 0 ? 'text-rose-600' : 'text-success']">{{ formatMoney(Math.abs(gain)) }}</dd>
          </div>
        </dl>
      </form>
      <DialogFooter>
        <Button variant="outline" @click="asset = null">{{ t("common.cancel") }}</Button>
        <Button
          type="submit"
          form="dispose-form"
          variant="destructive"
          class="active:scale-95"
          :disabled="dispose.isPending.value || (!!form.proceeds && !form.bank_id)"
          :loading="dispose.isPending.value"
        >
          <PackageMinus /> {{ t("assets.dispose") }}
        </Button>
      </DialogFooter>
    </DialogContent>
  </Dialog>
</template>
