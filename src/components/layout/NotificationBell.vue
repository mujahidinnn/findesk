<script setup lang="ts">
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";
import { formatDistanceToNow } from "date-fns";
import { Bell, BellRing, Check, CheckCheck, CircleCheck, CircleX, Clock, HandCoins, Trash2, TriangleAlert } from "@lucide/vue";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import EmptyState from "@/components/common/EmptyState.vue";
import { useClearReadNotifications, useMarkNotificationsRead, useNotifications } from "@/composables/useNotifications";
import { dateLocale } from "@/lib/dateLocale";
import { NAV_GROUPS } from "@/lib/navigation";
import { describeNotification, type NotificationTone } from "@/lib/notifications";
import type { Notification } from "@/lib/types";

const { t, te } = useI18n();
const router = useRouter();
const { query, unread: unreadQuery } = useNotifications();
const markRead = useMarkNotificationsRead();
const clearRead = useClearReadNotifications();
const items = computed(() => query.data.value?.pages.flat() ?? []);
const unread = computed(() => unreadQuery.data.value ?? 0);
const hasRead = computed(() => items.value.some((n) => n.is_read));
const tab = ref<"all" | "unread">("all");
const shown = computed(() => (tab.value === "unread" ? items.value.filter((n) => !n.is_read) : items.value));

const TONES: Record<NotificationTone, { icon: Component; class: string }> = {
  pending: { icon: Clock, class: "bg-orange-100 text-orange-700 dark:bg-orange-500/15 dark:text-orange-300" },
  approved: { icon: CircleCheck, class: "bg-green-500/15 text-green-700 dark:text-green-400" },
  paid: { icon: HandCoins, class: "bg-green-500/15 text-green-700 dark:text-green-400" },
  rejected: { icon: CircleX, class: "bg-rose-500/10 text-rose-700 dark:text-rose-400" },
  warning: { icon: TriangleAlert, class: "bg-orange-100 text-orange-700 dark:bg-orange-500/15 dark:text-orange-300" },
  neutral: { icon: Bell, class: "bg-muted text-muted-foreground" },
};
const view = (n: Notification) => {
  const { key, tone } = describeNotification(n.title);
  return { title: key && te(`notifications.titles.${key}`) ? t(`notifications.titles.${key}`) : n.title, ...TONES[tone] };
};
const target = (n: Notification) => {
  const path = n.link?.split("?")[0];
  const item = path ? NAV_GROUPS.flatMap((g) => g.items).find((i) => i.href === path) : undefined;
  return item ? t(`nav.items.${item.key}`) : "";
};

function open(n: Notification) {
  if (!n.is_read) markRead.mutate([n.id]);
  if (n.link?.startsWith("/")) router.push(n.link);
}
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger
      class="text-muted-foreground hover:bg-secondary hover:text-foreground relative rounded-md p-2"
      :aria-label="unread ? `${t('notifications.title')} (${unread})` : t('notifications.title')"
    >
      <component :is="unread ? BellRing : Bell" class="size-4" />
      <span
        v-if="unread"
        class="absolute top-0.5 right-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-rose-600 px-1 text-[9px] font-bold text-white tabular-nums"
      >
        {{ unread > 9 ? "9+" : unread }}
      </span>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end" class="w-96 max-w-[calc(100vw-1rem)] overflow-hidden p-0">
      <div class="flex items-center justify-between gap-2 px-4 pt-3 pb-2">
        <p class="text-sm font-semibold">{{ t("notifications.title") }}</p>
        <button
          v-if="unread"
          type="button"
          class="text-primary-text hover:bg-primary-soft flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium"
          @click="markRead.mutate(undefined)"
        >
          <CheckCheck class="size-3.5" /> {{ t("notifications.markAllRead") }}
        </button>
      </div>
      <div role="tablist" class="flex gap-1 border-b px-3">
        <button
          v-for="k in (['all', 'unread'] as const)"
          :key="k"
          type="button"
          role="tab"
          :aria-selected="tab === k"
          :class="['-mb-px border-b-2 px-2 pb-2 text-xs font-medium', tab === k ? 'border-primary text-foreground' : 'text-muted-foreground hover:text-foreground border-transparent']"
          @click="tab = k"
        >
          {{ t(`notifications.${k}`) }}<span v-if="k === 'unread' && unread" class="bg-primary-soft text-primary-text ml-1.5 rounded-full px-1.5 py-0.5 text-[10px] tabular-nums">{{ unread }}</span>
        </button>
      </div>

      <div class="scrollbar-thin max-h-96 overflow-y-auto">
        <EmptyState
          v-if="!shown.length"
          compact
          :icon="tab === 'unread' && items.length ? CheckCheck : Bell"
          :title="tab === 'unread' && items.length ? t('notifications.caughtUp') : t('notifications.empty')"
          :description="tab === 'unread' && items.length ? undefined : t('notifications.emptyHint')"
        />
        <DropdownMenuItem
          v-for="n in shown"
          :key="n.id"
          class="group flex items-start gap-3 rounded-none border-b px-4 py-3 last:border-0"
          :class="{ 'bg-primary/5': !n.is_read }"
          @select="open(n)"
        >
          <span :class="['mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full', view(n).class]">
            <component :is="view(n).icon" class="size-4 text-current" />
          </span>
          <span class="min-w-0 flex-1">
            <span :class="['block text-sm leading-snug', n.is_read ? 'font-medium' : 'font-semibold']">{{ view(n).title }}</span>
            <span v-if="n.body" class="text-muted-foreground mt-0.5 line-clamp-2 block text-xs">{{ n.body }}</span>
            <span class="text-muted-foreground mt-1 flex items-center gap-1.5 text-[11px]">
              <span v-if="target(n)" class="bg-secondary rounded-sm px-1.5 py-0.5 font-medium">{{ target(n) }}</span>
              {{ formatDistanceToNow(new Date(n.created_at), { addSuffix: true, locale: dateLocale() }) }}
            </span>
          </span>
          <button
            v-if="!n.is_read"
            type="button"
            class="text-muted-foreground hover:bg-secondary hover:text-foreground mt-0.5 shrink-0 rounded-md p-1.5"
            :title="t('notifications.markRead')"
            :aria-label="t('notifications.markRead')"
            @click.stop.prevent="markRead.mutate([n.id])"
          >
            <Check class="size-3.5" />
          </button>
        </DropdownMenuItem>
      </div>
      <div v-if="query.hasNextPage.value || hasRead" class="flex items-center justify-between gap-2 border-t px-3 py-2">
        <button
          v-if="query.hasNextPage.value"
          type="button"
          class="text-primary-text hover:bg-primary-soft rounded-md px-2 py-1 text-xs font-medium"
          :disabled="query.isFetchingNextPage.value"
          @click.prevent="query.fetchNextPage()"
        >
          {{ query.isFetchingNextPage.value ? t("common.loading") : t("notifications.loadMore") }}
        </button>
        <span v-else />
        <button
          v-if="hasRead"
          type="button"
          class="text-muted-foreground hover:bg-secondary hover:text-foreground flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium"
          :disabled="clearRead.isPending.value"
          @click.prevent="clearRead.mutate()"
        >
          <Trash2 class="size-3.5" /> {{ t("notifications.clearRead") }}
        </button>
      </div>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
