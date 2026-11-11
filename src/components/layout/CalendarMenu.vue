<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";
import { useQuery } from "@tanstack/vue-query";
import { PopoverContent, PopoverPortal, PopoverRoot, PopoverTrigger } from "reka-ui";
import { addMonths, eachDayOfInterval, endOfMonth, endOfWeek, format, isSameMonth, isToday, startOfMonth, startOfWeek } from "date-fns";
import { CalendarDays, ChevronLeft, ChevronRight } from "@lucide/vue";
import { supabase } from "@/integrations/supabase/client";
import { dateLocale } from "@/lib/dateLocale";
import { formatMoney, isoDate } from "@/lib/format";
import { cn } from "@/lib/utils";

const { t } = useI18n();
const router = useRouter();
const open = ref(false);
const month = ref(startOfMonth(new Date()));
const selected = ref(isoDate(new Date()));
const WEEK = { weekStartsOn: 1 } as const;
const days = computed(() => eachDayOfInterval({ start: startOfWeek(month.value, WEEK), end: endOfWeek(endOfMonth(month.value), WEEK) }));
const weekdays = computed(() => days.value.slice(0, 7).map((d) => format(d, "EEEEE", { locale: dateLocale() })));

interface Due { id: number; doc_no: string | null; doc_type: string; due_date: string; total: number; paid_amount: number; currency: string; partner: { name: string } | null }
const dues = useQuery({
  queryKey: computed(() => ["calendar-due", isoDate(days.value[0]!), isoDate(days.value.at(-1)!)]),
  enabled: open,
  queryFn: async () => {
    const { data, error } = await supabase
      .from("t_invoices")
      .select("id, doc_no, doc_type, due_date, total, paid_amount, currency, partner:m_partners(name)")
      .eq("status", "posted")
      .in("doc_type", ["sales_invoice", "purchase_bill"])
      .gte("due_date", isoDate(days.value[0]!))
      .lte("due_date", isoDate(days.value.at(-1)!))
      .order("due_date");
    if (error) throw error;
    return (data as unknown as Due[]).filter((d) => Number(d.total) > Number(d.paid_amount));
  },
});
const byDay = computed(() => {
  const m = new Map<string, Due[]>();
  for (const d of dues.data.value ?? []) m.set(d.due_date, [...(m.get(d.due_date) ?? []), d]);
  return m;
});
const list = computed(() => byDay.value.get(selected.value) ?? []);
const kinds = (iso: string) => new Set((byDay.value.get(iso) ?? []).map((d) => d.doc_type));

function go(d: Due) {
  open.value = false;
  router.push(`${d.doc_type === "sales_invoice" ? "/sales/invoices" : "/purchases/bills"}?id=${d.id}`);
}
function today() {
  month.value = startOfMonth(new Date());
  selected.value = isoDate(new Date());
}
</script>

<template>
  <PopoverRoot v-model:open="open">
    <PopoverTrigger
      class="text-muted-foreground hover:bg-secondary hover:text-foreground rounded-md p-2"
      :aria-label="t('calendar.title')"
      :title="t('calendar.title')"
    >
      <CalendarDays class="size-4" />
    </PopoverTrigger>
    <PopoverPortal>
      <PopoverContent
        align="end"
        :side-offset="8"
        class="bg-popover text-popover-foreground data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 z-50 w-80 max-w-[calc(100vw-1rem)] overflow-hidden rounded-lg border shadow-md"
      >
        <div class="flex items-center justify-between gap-1 px-3 pt-3">
          <p class="px-1 text-sm font-semibold capitalize">{{ format(month, "MMMM yyyy", { locale: dateLocale() }) }}</p>
          <div class="flex items-center gap-0.5">
            <button type="button" class="text-muted-foreground hover:bg-secondary rounded-md px-2 py-1 text-xs font-medium" @click="today">{{ t("calendar.today") }}</button>
            <button type="button" class="text-muted-foreground hover:bg-secondary rounded-md p-1.5" :aria-label="t('calendar.prev')" @click="month = addMonths(month, -1)"><ChevronLeft class="size-4" /></button>
            <button type="button" class="text-muted-foreground hover:bg-secondary rounded-md p-1.5" :aria-label="t('calendar.next')" @click="month = addMonths(month, 1)"><ChevronRight class="size-4" /></button>
          </div>
        </div>
        <div class="grid grid-cols-7 gap-y-0.5 p-3 text-center text-sm">
          <span v-for="(w, i) in weekdays" :key="i" class="text-muted-foreground pb-1 text-[11px] font-medium uppercase">{{ w }}</span>
          <button
            v-for="d in days"
            :key="isoDate(d)"
            type="button"
            :aria-pressed="selected === isoDate(d)"
            :class="cn(
              'relative mx-auto flex size-9 flex-col items-center justify-center rounded-md text-sm tabular-nums transition-colors',
              !isSameMonth(d, month) && 'text-muted-foreground/50',
              isToday(d) && 'font-semibold',
              selected === isoDate(d) ? 'bg-primary text-primary-foreground' : 'hover:bg-secondary',
              isToday(d) && selected !== isoDate(d) && 'ring-primary/40 ring-1',
            )"
            @click="selected = isoDate(d)"
          >
            {{ d.getDate() }}
            <span v-if="kinds(isoDate(d)).size" class="absolute bottom-1 flex gap-0.5">
              <span v-if="kinds(isoDate(d)).has('sales_invoice')" :class="['size-1 rounded-full', selected === isoDate(d) ? 'bg-primary-foreground' : 'bg-green-600']" />
              <span v-if="kinds(isoDate(d)).has('purchase_bill')" :class="['size-1 rounded-full', selected === isoDate(d) ? 'bg-primary-foreground/70' : 'bg-orange-500']" />
            </span>
          </button>
        </div>

        <div class="bg-muted/40 border-t px-3 py-2.5">
          <div class="text-muted-foreground mb-2 flex items-center justify-between text-[11px]">
            <span class="font-medium">{{ t("calendar.dueOn", { date: format(new Date(`${selected}T00:00:00`), "d MMM yyyy", { locale: dateLocale() }) }) }}</span>
            <span class="flex items-center gap-3">
              <span class="flex items-center gap-1"><span class="size-1.5 rounded-full bg-green-600" />{{ t("calendar.receivable") }}</span>
              <span class="flex items-center gap-1"><span class="size-1.5 rounded-full bg-orange-500" />{{ t("calendar.payable") }}</span>
            </span>
          </div>
          <p v-if="!list.length" class="text-muted-foreground py-3 text-center text-xs">{{ dues.isPending.value && open ? t("common.loading") : t("calendar.none") }}</p>
          <ul v-else class="scrollbar-thin max-h-40 space-y-1 overflow-y-auto">
            <li v-for="d in list" :key="d.id">
              <button type="button" class="hover:bg-secondary flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left" @click="go(d)">
                <span :class="['size-2 shrink-0 rounded-full', d.doc_type === 'sales_invoice' ? 'bg-green-600' : 'bg-orange-500']" />
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-xs font-medium">{{ d.partner?.name ?? "-" }}</span>
                  <span class="text-muted-foreground block font-mono text-[11px]">{{ d.doc_no }}</span>
                </span>
                <span class="shrink-0 text-xs font-medium tabular-nums">{{ formatMoney(Number(d.total) - Number(d.paid_amount), d.currency) }}</span>
              </button>
            </li>
          </ul>
        </div>
      </PopoverContent>
    </PopoverPortal>
  </PopoverRoot>
</template>
