<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";
import { refDebounced, useColorMode, useMagicKeys } from "@vueuse/core";
import { ArrowDown, ArrowUp, CornerDownLeft, FileText, ListTree, LogOut, Moon, UserCog, Users } from "@lucide/vue";
import {
  CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from "@/components/ui/command";
import { useNavGroups } from "@/composables/useNavGroups";
import { supabase } from "@/integrations/supabase/client";

const emit = defineEmits<{ signOut: [] }>();
const { t } = useI18n();
const router = useRouter();
const groups = useNavGroups();
const mode = useColorMode();
const open = ref(false);

const keys = useMagicKeys({
  passive: false,
  onEventFired(e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k" && e.type === "keydown") e.preventDefault();
  },
});
watch([keys["Ctrl+K"]!, keys["Meta+K"]!], ([a, b]) => {
  if (a || b) open.value = !open.value;
});

defineExpose({ show: () => (open.value = true) });

interface Hit { key: string; group: string; label: string; sub: string; to: string; icon: unknown }
const term = ref("");
const debounced = refDebounced(term, 300);
const hits = ref<Hit[]>([]);
watch(open, (v) => !v && (term.value = ""));
watch(debounced, async (raw) => {
  const s = raw.trim().replace(/[%_,()*]/g, "");
  if (s.length < 2) return (hits.value = []);
  const like = `%${s}%`;
  const [partners, accounts, invoices, payments, journals] = await Promise.all([
    supabase.from("m_partners").select("id, code, name").or(`name.ilike.${like},code.ilike.${like}`).limit(5),
    supabase.from("m_accounts").select("id, code, name").or(`name.ilike.${like},code.ilike.${like}`).eq("is_postable", true).limit(5),
    supabase.from("t_invoices").select("id, doc_no, doc_type, reference").or(`doc_no.ilike.${like},reference.ilike.${like}`).order("id", { ascending: false }).limit(6),
    supabase.from("t_payments").select("id, doc_no, direction").ilike("doc_no", like).order("id", { ascending: false }).limit(4),
    supabase.from("t_journals").select("id, doc_no, memo").or(`doc_no.ilike.${like},memo.ilike.${like}`).order("id", { ascending: false }).limit(5),
  ]);
  if (debounced.value !== raw) return;
  hits.value = [
    ...(partners.data ?? []).map((p) => ({ key: `p${p.id}`, group: "partners", label: p.name, sub: p.code, to: `/partners?id=${p.id}`, icon: Users })),
    ...(accounts.data ?? []).map((a) => ({ key: `a${a.id}`, group: "accounts", label: a.name, sub: a.code, to: `/ledger?account=${a.id}`, icon: ListTree })),
    ...[...(invoices.data ?? []), ...(payments.data ?? []), ...(journals.data ?? [])].map((d) => {
      const r = d as { id: number; doc_no: string | null; doc_type?: string; direction?: string; reference?: string | null; memo?: string | null };
      const to = r.doc_type ? (r.doc_type.startsWith("sales") ? "/sales/invoices" : "/purchases/bills")
        : r.direction ? (r.direction === "in" ? "/sales/receipts" : "/purchases/payments") : "/journals";
      return { key: `${to}${r.id}`, group: "documents", label: r.doc_no ?? `#${r.id}`, sub: r.reference ?? r.memo ?? "", to: `${to}?id=${r.id}`, icon: FileText };
    }),
  ];
});
const hitGroups = computed(() => [...new Set(hits.value.map((h) => h.group))].map((g) => ({ g, items: hits.value.filter((h) => h.group === g) })));

function run(action: () => void) {
  open.value = false;
  action();
}
</script>

<template>
  <CommandDialog v-model:open="open" :title="t('palette.title')" :description="t('palette.placeholder')">
    <CommandInput :placeholder="t('palette.placeholder')" @input="term = ($event.target as HTMLInputElement).value" />
    <CommandList>
      <CommandEmpty v-if="!hits.length">{{ t("palette.empty") }}</CommandEmpty>
      <div v-for="hg in hitGroups" :key="hg.g" class="p-1">
        <p class="text-muted-foreground px-2 py-1.5 text-xs font-medium">{{ t(`palette.${hg.g}`) }}</p>
        <CommandItem v-for="h in hg.items" :key="h.key" :value="`${h.label} ${h.sub}`" @select="run(() => router.push(h.to))">
          <component :is="h.icon" /> {{ h.label }}
          <span v-if="h.sub" class="text-muted-foreground ml-auto text-xs">{{ h.sub }}</span>
        </CommandItem>
      </div>
      <CommandGroup v-for="g in groups" :key="g.key" :heading="t(`nav.groups.${g.key}`)">
        <CommandItem
          v-for="item in g.items"
          :key="item.href"
          :value="t(`nav.items.${item.key}`)"
          @select="run(() => router.push(item.href))"
        >
          <component :is="item.icon" /> {{ t(`nav.items.${item.key}`) }}
        </CommandItem>
      </CommandGroup>
      <CommandGroup :heading="t('palette.actions')">
        <CommandItem value="profile" @select="run(() => router.push('/settings/profile'))">
          <UserCog /> {{ t("shell.profileSettings") }}
        </CommandItem>
        <CommandItem value="theme" @select="run(() => (mode = mode === 'dark' ? 'light' : 'dark'))">
          <Moon /> {{ t("palette.toggleTheme") }}
        </CommandItem>
        <CommandItem value="sign-out" @select="run(() => emit('signOut'))">
          <LogOut /> {{ t("shell.signOut") }}
        </CommandItem>
      </CommandGroup>
    </CommandList>
    <div class="text-muted-foreground bg-muted/50 hidden items-center gap-4 border-t px-4 py-2 text-xs sm:flex">
      <span class="flex items-center gap-1.5"><kbd class="bg-card flex size-6 items-center justify-center rounded-md border"><ArrowUp class="size-3.5" /></kbd><kbd class="bg-card flex size-6 items-center justify-center rounded-md border"><ArrowDown class="size-3.5" /></kbd> {{ t("palette.navigate") }}</span>
      <span class="flex items-center gap-1.5"><kbd class="bg-card flex size-6 items-center justify-center rounded-md border"><CornerDownLeft class="size-3.5" /></kbd> {{ t("palette.open") }}</span>
      <span class="flex items-center gap-1.5"><kbd class="bg-card flex h-6 items-center justify-center rounded-md border px-1.5 font-sans text-[11px] font-semibold">Esc</kbd> {{ t("common.close") }}</span>
      <span class="ml-auto">{{ t("palette.recordsHint") }}</span>
    </div>
  </CommandDialog>
</template>
