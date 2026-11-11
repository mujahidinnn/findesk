<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { toast } from "vue-sonner";
import { useMutation, useQuery, useQueryClient } from "@tanstack/vue-query";
import { Pencil, Plus, RefreshCw, Save } from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { usePermissions } from "@/composables/usePermissions";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";
import type { Tables } from "@/integrations/supabase/types";

type Currency = Tables<"m_currencies">;
const { t } = useI18n();
const { can } = usePermissions();
const serverError = useServerError();
const qc = useQueryClient();
const rows = useQuery({
  queryKey: ["m_currencies", "settings"],
  queryFn: async () => {
    const { data, error } = await supabase.from("m_currencies").select("*").order("code");
    if (error) throw error;
    return data;
  },
});

const editing = ref<Currency | null>(null);
const open = ref(false);
const form = ref({ code: "", name: "", symbol: "", is_active: true });
function openForm(row: Currency | null) {
  editing.value = row;
  form.value = row ? { code: row.code, name: row.name, symbol: row.symbol ?? "", is_active: row.is_active } : { code: "", name: "", symbol: "", is_active: true };
  open.value = true;
}
const save = useMutation({
  mutationFn: async () => {
    const values = { name: form.value.name.trim(), symbol: form.value.symbol.trim() || null, is_active: form.value.is_active };
    const { error } = editing.value
      ? await supabase.from("m_currencies").update(values).eq("code", editing.value.code)
      : await supabase.from("m_currencies").insert({ ...values, code: form.value.code.trim().toUpperCase() });
    if (error) throw error;
  },
  onSuccess: () => qc.invalidateQueries({ queryKey: ["m_currencies"] }),
});
async function submit() {
  try {
    await save.mutateAsync();
    open.value = false;
    toast.success(t("common.saved"));
  } catch (e) {
    toast.error(serverError(e));
  }
}
const list = computed(() => rows.data.value ?? []);
</script>

<template>
  <section class="space-y-3">
    <div class="toolbar">
      <h2 class="mr-auto font-semibold">{{ t("settings.currencies.title") }}</h2>
      <Button v-if="can('settings', 'create')" size="sm" @click="openForm(null)"><Plus /> {{ t("common.add") }}</Button>
    </div>
    <LoadingState v-if="rows.isPending.value" :columns="4" />
    <EmptyState v-else-if="rows.isError.value" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="rows.refetch()"><RefreshCw /> {{ t("common.retry") }}</Button>
    </EmptyState>
    <EmptyState v-else-if="!list.length" :title="t('common.empty')" />
    <div v-else class="bg-card overflow-x-auto rounded-xl border">
      <table class="w-full text-sm">
        <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
          <tr>
            <th class="w-px px-3 py-2 font-medium">{{ t("common.code") }}</th>
            <th class="px-3 py-2 font-medium">{{ t("common.name") }}</th>
            <th class="w-px px-3 py-2 font-medium">{{ t("settings.currencies.symbol") }}</th>
            <th class="w-px px-3 py-2 font-medium">{{ t("common.status") }}</th>
            <th class="w-px px-3 py-2"><span class="sr-only">{{ t("common.actions") }}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in list" :key="c.code" class="border-b last:border-0">
            <td class="px-3 py-2 font-mono text-xs">{{ c.code }}</td>
            <td class="px-3 py-2">{{ c.name }}</td>
            <td class="px-3 py-2">{{ c.symbol }}</td>
            <td class="px-3 py-2"><StatusBadge :tone="c.is_active ? 'success' : 'muted'">{{ c.is_active ? t("common.active") : t("common.inactive") }}</StatusBadge></td>
            <td class="px-3 py-1.5">
              <Button v-if="can('settings', 'update')" variant="ghost" size="icon" class="size-8" :tooltip="t('common.edit')" @click="openForm(c)"><Pencil /></Button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog v-model:open="open">
      <DialogContent class="sm:max-w-md">
        <DialogHeader><DialogTitle>{{ t("settings.currencies.title") }}</DialogTitle></DialogHeader>
        <form id="currency-form" class="space-y-3" @submit.prevent="submit">
          <div class="space-y-1.5">
            <Label for="cur-code">{{ t("common.code") }}</Label>
            <Input id="cur-code" v-model="form.code" class="font-mono uppercase" pattern="[A-Za-z]{3}" maxlength="3" required :disabled="!!editing" />
            <p class="text-muted-foreground text-xs">{{ t("settings.currencies.codeHint") }}</p>
          </div>
          <div class="space-y-1.5">
            <Label for="cur-name">{{ t("common.name") }}</Label>
            <Input id="cur-name" v-model="form.name" maxlength="60" required />
          </div>
          <div class="space-y-1.5">
            <Label for="cur-symbol">{{ t("settings.currencies.symbol") }}</Label>
            <Input id="cur-symbol" v-model="form.symbol" maxlength="5" />
          </div>
          <label class="flex items-center gap-2 text-sm"><input v-model="form.is_active" type="checkbox" class="accent-primary size-4" /> {{ t("common.active") }}</label>
        </form>
        <DialogFooter>
          <Button variant="outline" @click="open = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="currency-form" class="active:scale-95" :disabled="save.isPending.value" :loading="save.isPending.value"><Save /> {{ t("common.save") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </section>
</template>
