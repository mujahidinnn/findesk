<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { useRoute } from "vue-router";
import LogoMark from "@/components/brand/LogoMark.vue";
import AccountMenu from "./AccountMenu.vue";
import { useNavGroups } from "@/composables/useNavGroups";
import { useSettings } from "@/composables/useSettings";
import { cn } from "@/lib/utils";

defineEmits<{ navigate: []; signOut: [] }>();
const { t } = useI18n();
const route = useRoute();
const groups = useNavGroups();
const settings = useSettings();

const isActive = (href: string) => (href === "/" ? route.path === "/" : route.path.startsWith(href));
</script>

<template>
  <aside class="bg-sidebar text-sidebar-foreground border-sidebar-border flex h-full w-60 flex-col border-r">
    <div class="flex h-14 shrink-0 items-center gap-2.5 px-5">
      <img v-if="settings.data.value?.logo_url" :src="settings.data.value.logo_url" alt="" class="size-7 shrink-0 rounded-md object-contain" />
      <LogoMark v-else color class="size-6 shrink-0" />
      <p class="text-sidebar-accent-foreground text-[15px] font-semibold tracking-tight">FinDesk</p>
    </div>

    <nav class="scrollbar-sidebar flex-1 overflow-y-auto px-3 py-2" :aria-label="t('shell.navigation')">
      <div v-for="group in groups" :key="group.key" class="mb-4">
        <p class="text-sidebar-foreground/60 px-2.5 pb-1 text-xs font-medium">{{ t(`nav.groups.${group.key}`) }}</p>
        <RouterLink
          v-for="item in group.items"
          :key="item.href"
          :to="item.href"
          :aria-current="isActive(item.href) ? 'page' : undefined"
          :class="
            cn(
              'flex items-center gap-2.5 rounded-md px-2.5 py-[7px] text-[13.5px] transition-colors duration-150',
              isActive(item.href)
                ? 'bg-sidebar-accent text-sidebar-accent-foreground font-medium'
                : 'hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground',
            )
          "
          @click="$emit('navigate')"
        >
          <component :is="item.icon" class="size-4 shrink-0" :class="isActive(item.href) ? 'text-primary-text' : 'opacity-60'" />
          <span class="truncate">{{ t(`nav.items.${item.key}`) }}</span>
        </RouterLink>
      </div>
    </nav>
    <div class="border-sidebar-border shrink-0 border-t p-2"><AccountMenu @sign-out="$emit('signOut')" /></div>
  </aside>
</template>
