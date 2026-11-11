<script setup lang="ts">
import { RotateCcw, Sprout } from "@lucide/vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useQuery, useQueryClient } from "@tanstack/vue-query";
import { toast } from "vue-sonner";
import AppSelect from "@/components/common/AppSelect.vue";
import ConfirmDialog from "@/components/common/ConfirmDialog.vue";
import DocTable from "@/components/common/DocTable.vue";
import EmptyState from "@/components/common/EmptyState.vue";
import LoadingState from "@/components/common/LoadingState.vue";
import StatusBadge from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useMasterRows } from "@/composables/useMasterRows";
import { useServerError } from "@/composables/useServerError";
import { supabase } from "@/integrations/supabase/client";

const CONFIRM_WORD = "RESET";

const { t } = useI18n();
const qc = useQueryClient();
const serverError = useServerError();
const resetOpen = ref(false);
const seedOpen = ref(false);
const typed = ref("");
const busy = ref(false);

interface Overview {
  counts: { users: number; partners: number; accounts: number; journals: number; invoices: number; open_periods: number; demo_mode: boolean };
  journals_14d: { day: string; count: number }[];
  last_audit: { at: string; action: string; entity: string }[];
  last_errors: { at: string; source: string; message: string }[];
}
const overview = useQuery({
  queryKey: ["superadmin-overview"],
  queryFn: async () => {
    const { data, error } = await supabase.rpc("superadmin_overview");
    if (error) throw error;
    return data as unknown as Overview;
  },
});
const o = computed(() => overview.data.value);
const maxDay = computed(() => Math.max(1, ...(o.value?.journals_14d ?? []).map((d) => Number(d.count))));
const STATS = ["users", "partners", "accounts", "journals", "invoices", "open_periods"] as const;
const stamp = (iso: unknown) => new Date(String(iso)).toLocaleString("id-ID");
const day = (iso: string) => new Date(`${iso.slice(0, 10)}T00:00`).toLocaleDateString("id-ID", { day: "numeric", month: "short" });

const errors = useMasterRows("t_error_log", { order: "created_at", descending: true });
const errorSource = ref<string | null>(null);
const sources = computed(() => [...new Set((errors.data.value ?? []).map((r) => String(r.source)))].sort().map((v) => ({ value: v, label: v })));
const errorRows = computed(() => (errors.data.value ?? []).filter((r) => !errorSource.value || r.source === errorSource.value));
const json = (v: unknown) => JSON.stringify(v, null, 2);

async function seedDemo() {
  busy.value = true;
  try {
    const { data, error } = await supabase.rpc("seed_demo_data");
    if (error) throw error;
    const r = (data ?? {}) as { skipped?: boolean; journals?: number; invoices?: number };
    await qc.invalidateQueries();
    seedOpen.value = false;
    if (r.skipped) toast.info(t("system.seedSkipped"));
    else toast.success(t("system.seedDone", { journals: r.journals ?? 0, invoices: r.invoices ?? 0 }));
  } catch (e) {
    toast.error(serverError(e));
  } finally {
    busy.value = false;
  }
}

async function reset() {
  if (typed.value !== CONFIRM_WORD) return;
  busy.value = true;
  try {
    const { error } = await supabase.rpc("superadmin_reset_data");
    if (error) throw error;
    resetOpen.value = false;
    await qc.invalidateQueries();
    toast.success(t("system.resetDone"));
  } catch (e) {
    toast.error(serverError(e));
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="space-y-6">
    <LoadingState v-if="overview.isPending.value" variant="cards" />
    <EmptyState v-else-if="overview.isError.value" class="bg-card rounded-xl border" :title="t('common.loadFailed')">
      <Button variant="outline" size="sm" @click="overview.refetch()">{{ t("common.retry") }}</Button>
    </EmptyState>
    <template v-else-if="o">
      <div class="grid gap-3 sm:grid-cols-3 lg:grid-cols-7">
        <div v-for="k in STATS" :key="k" class="bg-card rounded-xl border p-3">
          <p class="text-muted-foreground text-xs">{{ t(`system.stats.${k}`) }}</p>
          <p class="text-xl font-semibold tabular-nums">{{ Number(o.counts[k]).toLocaleString("id-ID") }}</p>
        </div>
        <div class="bg-card rounded-xl border p-3">
          <p class="text-muted-foreground text-xs">{{ t("system.stats.demo_mode") }}</p>
          <StatusBadge class="mt-1.5" :tone="o.counts.demo_mode ? 'warning' : 'muted'">{{ o.counts.demo_mode ? t("common.yes") : t("common.no") }}</StatusBadge>
        </div>
      </div>

      <section class="bg-card space-y-2 rounded-xl border p-5">
        <h2 class="text-muted-foreground text-sm font-medium">{{ t("system.journals14d") }}</h2>
        <div class="flex h-28 items-end gap-1">
          <div
            v-for="d in o.journals_14d"
            :key="d.day"
            class="bg-primary/70 min-w-0 flex-1 rounded-t"
            :style="{ height: `${Math.max(2, (Number(d.count) / maxDay) * 100)}%` }"
            :title="`${day(d.day)}: ${d.count}`"
          />
        </div>
        <div v-if="o.journals_14d.length" class="text-muted-foreground flex justify-between text-[10px]">
          <span>{{ day(o.journals_14d[0].day) }}</span><span>{{ day(o.journals_14d[o.journals_14d.length - 1].day) }}</span>
        </div>
      </section>

      <div class="grid gap-6 lg:grid-cols-2">
        <section class="space-y-2">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold">{{ t("system.lastAudit") }}</h2>
            <RouterLink to="/audit" class="text-primary-text text-xs font-medium hover:underline">{{ t("system.openAudit") }}</RouterLink>
          </div>
          <div class="bg-card divide-y rounded-xl border text-sm">
            <EmptyState v-if="!o.last_audit.length" :title="t('common.empty')" compact />
            <div v-for="(a, i) in o.last_audit" :key="i" class="flex gap-2 px-3 py-2">
              <span class="text-muted-foreground shrink-0 text-xs tabular-nums">{{ stamp(a.at) }}</span>
              <span class="truncate">{{ a.action }} · {{ a.entity }}</span>
            </div>
          </div>
        </section>
        <section class="space-y-2">
          <h2 class="text-sm font-semibold">{{ t("system.lastErrors") }}</h2>
          <div class="bg-card divide-y rounded-xl border text-sm">
            <EmptyState v-if="!o.last_errors.length" :title="t('common.empty')" compact />
            <div v-for="(e, i) in o.last_errors" :key="i" class="space-y-0.5 px-3 py-2">
              <p class="text-muted-foreground text-xs tabular-nums">{{ stamp(e.at) }} · {{ e.source }}</p>
              <p class="truncate text-xs">{{ e.message }}</p>
            </div>
          </div>
        </section>
      </div>
    </template>

    <DocTable
      :title="t('system.errorLog')"
      :columns="[t('system.when'), t('system.source'), t('system.message'), t('common.detail')]"
      :rows="errorRows"
      :pending="errors.isPending.value"
      :failed="errors.isError.value"
      @retry="errors.refetch()"
    >
      <template #toolbar>
        <AppSelect v-model="errorSource" :options="sources" :null-label="t('system.allSources')" class="w-44" :aria-label="t('system.source')" />
      </template>
      <template #row="{ row }">
        <td class="text-xs whitespace-nowrap tabular-nums" :data-label="t('system.when')">{{ stamp(row.created_at) }}</td>
        <td class="font-mono text-xs" :data-label="t('system.source')">{{ row.source }}</td>
        <td class="max-w-md text-xs break-words" :data-label="t('system.message')">{{ row.message }}</td>
        <td :data-label="t('common.detail')">
          <details v-if="row.context || row.user_id">
            <summary class="text-muted-foreground cursor-pointer text-xs select-none">JSON</summary>
            <pre class="bg-secondary mt-1 max-h-60 max-w-md overflow-auto rounded p-2 text-[11px]">{{ json({ user_id: row.user_id, ...(row.context as object) }) }}</pre>
          </details>
        </td>
      </template>
    </DocTable>

    <div class="grid gap-4 lg:grid-cols-2">
      <section class="bg-card flex gap-4 rounded-xl border p-5">
        <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-green-500/15 text-green-700 dark:text-green-400"><Sprout class="size-5" /></span>
        <div class="flex flex-1 flex-col gap-3">
          <div>
            <h2 class="font-semibold">{{ t("system.seedTitle") }}</h2>
            <p class="text-muted-foreground mt-1 text-sm">{{ t("system.seedBody") }}</p>
          </div>
          <Button variant="outline" class="mt-auto w-fit active:scale-95" :disabled="busy" @click="seedOpen = true"><Sprout /> {{ t("system.seedAction") }}</Button>
        </div>
      </section>

      <section class="flex gap-4 rounded-xl border border-rose-200 bg-rose-50/60 p-5 dark:border-rose-500/30 dark:bg-rose-500/5">
        <span class="bg-destructive/10 text-destructive flex size-10 shrink-0 items-center justify-center rounded-xl"><RotateCcw class="size-5" /></span>
        <div class="flex flex-1 flex-col gap-3">
          <div>
            <h2 class="font-semibold">{{ t("system.resetTitle") }}</h2>
            <p class="text-muted-foreground mt-1 text-sm">{{ t("system.resetBody") }}</p>
          </div>
          <Button variant="destructive" class="mt-auto w-fit active:scale-95" :disabled="busy" @click="((typed = ''), (resetOpen = true))"><RotateCcw /> {{ t("system.resetAction") }}</Button>
        </div>
      </section>
    </div>

    <ConfirmDialog
      v-model:open="seedOpen"
      :title="t('system.seedConfirmTitle')"
      :description="t('system.seedConfirmBody')"
      :confirm-label="t('system.seedAction')"
      :busy="busy"
      @confirm="seedDemo"
    />

    <Dialog v-model:open="resetOpen">
      <DialogContent class="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>{{ t("system.confirmTitle") }}</DialogTitle>
          <DialogDescription>{{ t("system.confirmBody", { word: CONFIRM_WORD }) }}</DialogDescription>
        </DialogHeader>
        <form id="reset-form" class="space-y-1.5" @submit.prevent="reset">
          <Label for="reset-confirm" class="sr-only">{{ CONFIRM_WORD }}</Label>
          <Input id="reset-confirm" v-model="typed" autocomplete="off" :placeholder="CONFIRM_WORD" />
        </form>
        <DialogFooter>
          <Button variant="outline" @click="resetOpen = false">{{ t("common.cancel") }}</Button>
          <Button type="submit" form="reset-form" variant="destructive" :disabled="busy || typed !== CONFIRM_WORD" :loading="busy"><RotateCcw /> {{ t("system.resetAction") }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
