<script setup lang="ts">
import { computed, onErrorCaptured, onUnmounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { useRoute, useRouter } from "vue-router";
import { ChevronRight, Menu, Search } from "@lucide/vue";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import Sidebar from "./Sidebar.vue";
import CalendarMenu from "./CalendarMenu.vue";
import NotificationBell from "./NotificationBell.vue";
import CommandPalette from "./CommandPalette.vue";
import SignOutConfirmModal from "./SignOutConfirmModal.vue";
import PageFallback from "./PageFallback.vue";
import { useAuthStore } from "@/stores/auth";
import { logClientError } from "@/lib/errorLog";
import { NAV_GROUPS } from "@/lib/navigation";

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

const palette = ref<InstanceType<typeof CommandPalette> | null>(null);
const mobileNav = ref(false);
const signOutOpen = ref(false);
const pageError = ref(false);
const pageKey = ref(0);
const navLoading = ref(false);
const stopNav = [
  router.beforeEach(() => void (navLoading.value = true)),
  router.afterEach(() => void (navLoading.value = false)),
  router.onError(() => void (navLoading.value = false)),
];
onUnmounted(() => stopNav.forEach((stop) => stop()));

const title = computed(() => (route.meta.title ? t(route.meta.title) : ""));
const subtitle = computed(() => (route.meta.subtitle ? t(route.meta.subtitle) : ""));
const crumbGroup = computed(() => {
  const g = NAV_GROUPS.find((grp) => grp.items.some((i) => (i.href === "/" ? route.path === "/" : route.path.startsWith(i.href))));
  return g ? t(`nav.groups.${g.key}`) : "";
});
const isMac = /Mac|iPhone|iPad/.test(navigator.platform);

onErrorCaptured((err) => {
  logClientError("page", err instanceof Error ? err.message : String(err), { path: route.fullPath });
  pageError.value = true;
  return false;
});
watch(() => route.fullPath, () => (pageError.value = false));

function retry() {
  pageError.value = false;
  pageKey.value++;
}

async function signOut() {
  await auth.signOut();
  router.replace("/login");
}
</script>

<template>
  <div class="bg-background flex h-full overflow-hidden">
    <CommandPalette ref="palette" @sign-out="signOutOpen = true" />
    <SignOutConfirmModal v-model:open="signOutOpen" :on-confirm="signOut" />

    <div class="hidden shrink-0 lg:block"><Sidebar @sign-out="signOutOpen = true" /></div>
    <Sheet v-model:open="mobileNav">
      <SheetContent side="left" class="w-60 border-0 bg-transparent p-0 shadow-none [&>button]:hidden">
        <SheetTitle class="sr-only">{{ t("shell.navigation") }}</SheetTitle>
        <SheetDescription class="sr-only">{{ t("shell.navigation") }}</SheetDescription>
        <Sidebar @navigate="mobileNav = false" @sign-out="(mobileNav = false), (signOutOpen = true)" />
      </SheetContent>
    </Sheet>

    <div class="relative flex min-w-0 flex-1 flex-col">
      <div v-if="navLoading" class="bg-primary/15 absolute inset-x-0 top-0 z-20 h-0.5 overflow-hidden">
        <div class="nav-progress bg-brand-strong h-full w-1/3 rounded-full" />
      </div>
      <header class="bg-background/80 flex h-14 shrink-0 items-center gap-3 border-b px-3 backdrop-blur md:px-8">
        <button
          type="button"
          class="text-muted-foreground hover:bg-secondary rounded-md p-1.5 lg:hidden"
          :aria-label="t('shell.openMenu')"
          @click="mobileNav = true"
        >
          <Menu class="size-5" />
        </button>
        <nav v-if="crumbGroup" class="hidden shrink-0 items-center gap-1.5 text-sm sm:flex" :aria-label="t('shell.navigation')">
          <span class="text-muted-foreground">{{ crumbGroup }}</span>
          <ChevronRight class="text-muted-foreground size-3.5" />
          <span class="font-medium">{{ title }}</span>
        </nav>

        <button
          type="button"
          class="bg-card hover:border-input text-muted-foreground ml-auto flex h-9 w-full min-w-0 max-w-sm items-center gap-2 rounded-md border px-3 text-sm transition-colors duration-150"
          @click="palette?.show()"
        >
          <Search class="size-4" />
          <span class="flex-1 truncate text-left">{{ t("shell.search") }}</span>
          <kbd class="bg-card hidden rounded-sm border px-1.5 py-0.5 font-sans text-[10px] font-semibold sm:block">
            {{ isMac ? "⌘" : "Ctrl" }} K
          </kbd>
        </button>

        <div class="flex shrink-0 items-center gap-1">
          <CalendarMenu />
          <NotificationBell />
        </div>
      </header>

      <main class="scrollbar-thin flex flex-1 flex-col overflow-y-auto px-4 pt-8 pb-8 transition-opacity md:px-10" :class="navLoading && 'pointer-events-none opacity-50'">
        <div v-if="title" class="mb-7">
          <h1 class="text-[28px] leading-tight font-semibold tracking-[-0.025em]">{{ title }}</h1>
          <p v-if="subtitle" class="text-muted-foreground mt-1 max-w-[70ch] text-sm">{{ subtitle }}</p>
        </div>
        <PageFallback v-if="pageError" @retry="retry" />
        <div v-else :key="`${pageKey}-${route.path}`" class="page-enter"><RouterView /></div>
        <p class="text-muted-foreground mt-auto pt-10 text-center text-[11px]">{{ t("app.copyright", { year: new Date().getFullYear() }) }}</p>
      </main>
    </div>
  </div>
</template>
