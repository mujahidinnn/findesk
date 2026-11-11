<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import {
  ArrowRight, BookOpenCheck, Calculator, CalendarCheck, ChartColumn, Eye, FileInput, GitCompareArrows, Landmark, Percent, Receipt, Search,
  ShieldCheck, UserCog, UserRound, Building2, Wallet,
} from "@lucide/vue";
import EmptyState from "@/components/common/EmptyState.vue";
import { Input } from "@/components/ui/input";

const { t, tm, rt } = useI18n();
const ROLES = [
  { key: "admin", icon: UserCog }, { key: "manager", icon: ShieldCheck }, { key: "accountant", icon: Calculator },
  { key: "staff", icon: Wallet }, { key: "auditor", icon: Eye }, { key: "employee", icon: UserRound },
] as const;
const TOPICS = [
  { key: "sales", icon: Receipt, to: "/sales/invoices" }, { key: "purchases", icon: FileInput, to: "/purchases/bills" },
  { key: "cash", icon: Landmark, to: "/cash" }, { key: "reconcile", icon: GitCompareArrows, to: "/reconcile" },
  { key: "tax", icon: Percent, to: "/tax" }, { key: "assets", icon: Building2, to: "/assets" },
  { key: "closing", icon: CalendarCheck, to: "/periods" }, { key: "approval", icon: BookOpenCheck, to: "/approvals" },
  { key: "reports", icon: ChartColumn, to: "/reports" },
] as const;
const items = (key: string) => (tm(`guide.topics.${key}.items`) as unknown as Parameters<typeof rt>[0][]).map((m) => rt(m));
const q = ref("");
const term = computed(() => q.value.trim().toLowerCase());
const match = (text: string[]) => !term.value || text.join(" ").toLowerCase().includes(term.value);
const roles = computed(() => ROLES.filter((r) => match([t(`guide.roles.${r.key}.title`), t(`guide.roles.${r.key}.body`)])));
const topics = computed(() => TOPICS.filter((x) => match([t(`guide.topics.${x.key}.title`), ...items(x.key)])));
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center gap-3">
      <p class="text-muted-foreground max-w-2xl text-sm">{{ t("guide.intro") }}</p>
      <div class="relative ml-auto w-full sm:w-64">
        <Search class="text-muted-foreground absolute top-1/2 left-2.5 size-4 -translate-y-1/2" />
        <Input v-model="q" type="search" class="pl-8" :placeholder="t('common.search')" :aria-label="t('common.search')" />
      </div>
    </div>

    <template v-if="roles.length">
      <h2 class="text-lg font-semibold tracking-tight">{{ t("guide.rolesTitle") }}</h2>
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <section v-for="r in roles" :key="r.key" class="bg-card flex gap-3 rounded-xl border p-5">
          <span class="bg-primary-soft text-primary-text flex size-10 shrink-0 items-center justify-center rounded-xl"><component :is="r.icon" class="size-5" /></span>
          <div>
            <h3 class="font-semibold">{{ t(`guide.roles.${r.key}.title`) }}</h3>
            <p class="text-muted-foreground mt-1 text-sm">{{ t(`guide.roles.${r.key}.body`) }}</p>
          </div>
        </section>
      </div>
    </template>

    <h2 class="pt-2 text-lg font-semibold tracking-tight">{{ t("guide.topicsTitle") }}</h2>
    <EmptyState v-if="!topics.length && !roles.length" class="bg-card rounded-xl border" :title="t('guide.noMatch')" />
    <div class="grid gap-4 lg:grid-cols-2">
      <section v-for="topic in topics" :key="topic.key" class="bg-card rounded-xl border p-5">
        <h3 class="flex items-center gap-2 font-semibold">
          <component :is="topic.icon" class="text-primary-text size-4" /> {{ t(`guide.topics.${topic.key}.title`) }}
          <RouterLink :to="topic.to" class="text-primary-text ml-auto flex items-center gap-1 text-xs font-medium hover:underline">
            {{ t("guide.open") }} <ArrowRight class="size-3.5" />
          </RouterLink>
        </h3>
        <ol class="mt-3 space-y-2 text-sm">
          <li v-for="(item, i) in items(topic.key)" :key="item" class="flex gap-2.5">
            <span class="bg-secondary text-muted-foreground flex size-5 shrink-0 items-center justify-center rounded-full text-[10px] font-semibold tabular-nums">{{ i + 1 }}</span>
            <span class="text-muted-foreground">{{ item }}</span>
          </li>
        </ol>
      </section>
    </div>
  </div>
</template>
