<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { keepPreviousData, useQuery } from "@tanstack/vue-query";
import { Info } from "@lucide/vue";
import AppSelect from "@/components/common/AppSelect.vue";
import DocTable from "@/components/common/DocTable.vue";
import ExportMenu from "@/components/common/ExportMenu.vue";
import PeriodFilter from "@/components/common/PeriodFilter.vue";
import StatusBadge, { type Tone } from "@/components/common/StatusBadge.vue";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { MasterRow } from "@/composables/useMasterRows";
import { useMasterRows } from "@/composables/useMasterRows";
import { supabase } from "@/integrations/supabase/client";
import { formatDate, isoDate } from "@/lib/format";

interface AuditRow extends MasterRow {
  action: string;
  entity_type: string;
  entity_id: string;
  created_at: string;
  detail: { before?: Record<string, unknown>; after?: Record<string, unknown> } | null;
  actor: { full_name: string | null } | null;
}

const { t, te } = useI18n();
const ENTITIES = [
  "invoice", "payment", "t_cash_txns", "t_bank_transfers", "t_expense_claims", "t_bank_statements", "asset", "period", "fiscal_year",
  "m_accounts", "m_account_map", "m_taxes", "m_partners", "m_bank_accounts", "m_currencies", "settings", "profile", "role_permission", "access_override",
];
const entityLabel = (e: string) => (te(`audit.entities.${e}`) ? t(`audit.entities.${e}`) : e);
const actionLabel = (a: string) => (te(`audit.actions.${a}`) ? t(`audit.actions.${a}`) : a);
const TONE: Record<string, Tone> = { insert: "success", update: "info", delete: "danger" };

const from = ref(isoDate(new Date(Date.now() - 29 * 86400000)));
const to = ref(isoDate());
const entity = ref<string | null>(null);
const actor = ref<string | null>(null);
const profiles = useMasterRows("profiles", { columns: "id, full_name", order: "full_name" });
const actorOptions = computed(() => (profiles.data.value ?? []).map((p) => ({ value: String(p.id), label: String(p.full_name ?? "-") })));

const LIMIT = 500;
// ponytail: newest 500 rows of the filtered range; add server paging if one range routinely holds more.
const log = useQuery({
  queryKey: computed(() => ["t_audit_log", from.value, to.value, entity.value, actor.value]),
  placeholderData: keepPreviousData,
  queryFn: async () => {
    const end = new Date(`${to.value}T00:00`);
    end.setDate(end.getDate() + 1);
    let q = supabase
      .from("t_audit_log")
      .select("*, actor:profiles(full_name)")
      .gte("created_at", new Date(`${from.value}T00:00`).toISOString())
      .lt("created_at", end.toISOString())
      .order("created_at", { ascending: false })
      .limit(LIMIT);
    if (entity.value) q = q.eq("entity_type", entity.value);
    if (actor.value) q = q.eq("actor_id", actor.value);
    const { data, error } = await q;
    if (error) throw error;
    return data as unknown as AuditRow[];
  },
});
const rows = computed(() => log.data.value ?? []);

const IGNORED = new Set(["updated_at"]);
function changes(row: AuditRow) {
  const before = row.detail?.before ?? {};
  const after = row.detail?.after ?? {};
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter((k) => !IGNORED.has(k));
  return keys
    .filter((k) => JSON.stringify(before[k]) !== JSON.stringify(after[k]))
    .map((k) => ({ key: k, before: before[k], after: after[k] }));
}
const show = (v: unknown) => (v == null ? "–" : typeof v === "object" ? JSON.stringify(v) : String(v));

const open = ref<AuditRow | null>(null);
const openChanges = computed(() => (open.value ? changes(open.value) : []));
const stamp = (iso: string) => formatDate(iso, true);
const exportRows = () =>
  rows.value.map((r) => ({
    [t("audit.when")]: stamp(r.created_at),
    [t("audit.actor")]: r.actor?.full_name ?? "",
    [t("audit.action")]: actionLabel(r.action),
    [t("audit.entity")]: entityLabel(r.entity_type),
    ID: r.entity_id,
    [t("audit.changes")]: changes(r).map((c) => `${c.key}: ${show(c.before)} → ${show(c.after)}`).join("; "),
  }));
</script>

<template>
  <div class="space-y-4">
    <DocTable
      :title="t('audit.title')"
      :columns="[t('audit.when'), t('audit.actor'), t('audit.action'), t('audit.entity'), t('audit.changes'), '']"
      :rows="rows"
      :pending="log.isPending.value"
      :failed="log.isError.value"
      @retry="log.refetch()"
    >
      <template #toolbar>
        <PeriodFilter v-model:from="from" v-model:to="to" />
        <AppSelect v-model="entity" :options="ENTITIES.map((e) => ({ value: e, label: entityLabel(e) }))" :null-label="t('audit.allEntities')" class="w-44" :aria-label="t('audit.entity')" />
        <AppSelect v-model="actor" :options="actorOptions" :null-label="t('audit.allActors')" class="w-44" :aria-label="t('audit.actor')" />
        <ExportMenu name="audit" :title="t('audit.title')" :rows="exportRows" :disabled="!rows.length" />
      </template>
      <template #row="{ row }">
        <td class="text-xs whitespace-nowrap tabular-nums" :data-label="t('audit.when')">{{ stamp((row as AuditRow).created_at) }}</td>
        <td :data-label="t('audit.actor')">{{ (row as AuditRow).actor?.full_name ?? t("audit.system") }}</td>
        <td :data-label="t('audit.action')"><StatusBadge :tone="TONE[(row as AuditRow).action] ?? 'muted'">{{ actionLabel((row as AuditRow).action) }}</StatusBadge></td>
        <td class="text-xs" :data-label="t('audit.entity')">{{ entityLabel((row as AuditRow).entity_type) }} <span class="text-muted-foreground font-mono">#{{ (row as AuditRow).entity_id }}</span></td>
        <td class="text-muted-foreground max-w-xs truncate text-xs" :data-label="t('audit.changes')">{{ changes(row as AuditRow).map((c) => c.key).join(", ") || "–" }}</td>
        <td data-label="">
          <Button variant="ghost" size="icon" class="size-8" :tooltip="t('common.detail')" @click="open = row as AuditRow"><Info /></Button>
        </td>
      </template>
    </DocTable>
    <p v-if="rows.length >= LIMIT" class="text-muted-foreground text-xs">{{ t("audit.limited", { n: LIMIT }) }}</p>

    <Dialog :open="!!open" @update:open="(v) => !v && (open = null)">
      <DialogContent class="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{{ open && `${actionLabel(open.action)} · ${entityLabel(open.entity_type)} #${open.entity_id}` }}</DialogTitle>
          <DialogDescription>{{ open && `${stamp(open.created_at)} · ${open.actor?.full_name ?? t("audit.system")}` }}</DialogDescription>
        </DialogHeader>
        <div v-if="openChanges.length" class="max-h-[60vh] overflow-auto rounded-xl border">
          <table class="w-full text-sm">
            <thead class="text-muted-foreground bg-muted/60 border-b text-left text-xs">
              <tr><th class="px-3 py-2 font-medium">{{ t("audit.field") }}</th><th class="px-3 py-2 font-medium">{{ t("audit.before") }}</th><th class="px-3 py-2 font-medium">{{ t("audit.after") }}</th></tr>
            </thead>
            <tbody>
              <tr v-for="c in openChanges" :key="c.key" class="border-b align-top last:border-0">
                <td class="px-3 py-2 font-mono text-xs">{{ c.key }}</td>
                <td class="px-3 py-2 text-xs break-all text-rose-700 dark:text-rose-400">{{ show(c.before) }}</td>
                <td class="text-success px-3 py-2 text-xs break-all">{{ show(c.after) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="text-muted-foreground text-sm">{{ t("audit.noChanges") }}</p>
      </DialogContent>
    </Dialog>
  </div>
</template>
