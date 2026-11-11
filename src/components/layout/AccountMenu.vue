<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { useRouter } from "vue-router";
import { useColorMode } from "@vueuse/core";
import { ChevronsUpDown, LogOut, Monitor, Moon, Sun, SunMoon, UserCog } from "@lucide/vue";
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useAuthStore } from "@/stores/auth";

const emit = defineEmits<{ signOut: [] }>();
const { t } = useI18n();
const router = useRouter();
const auth = useAuthStore();
const { store: themePref } = useColorMode();
const initials = computed(() =>
  (auth.profile?.full_name ?? "?").split(" ").map((w) => w[0]).slice(0, 2).join("").toUpperCase(),
);
const themes = [
  { value: "light", icon: Sun, label: "shell.themeLight" },
  { value: "dark", icon: Moon, label: "shell.themeDark" },
  { value: "auto", icon: Monitor, label: "shell.themeSystem" },
] as const;
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger class="hover:bg-sidebar-accent data-[state=open]:bg-sidebar-accent flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left transition-colors">
      <img v-if="auth.profile?.avatar_url" :src="auth.profile.avatar_url" alt="" class="size-8 shrink-0 rounded-md object-cover" />
      <span v-else class="bg-brand-100 text-brand-800 dark:bg-brand-900 dark:text-brand-200 flex size-8 shrink-0 items-center justify-center rounded-md text-[11px] font-bold">
        {{ initials }}
      </span>
      <span class="min-w-0 flex-1">
        <span class="text-sidebar-accent-foreground block truncate text-sm font-medium">{{ auth.profile?.full_name }}</span>
        <span class="text-sidebar-foreground/70 block truncate text-xs">{{ auth.isSuperadmin ? "Superadmin" : (auth.profile?.role?.role_name ?? "-") }}</span>
      </span>
      <ChevronsUpDown class="text-sidebar-foreground/60 size-4 shrink-0" />
    </DropdownMenuTrigger>
    <DropdownMenuContent side="top" align="start" :side-offset="6" class="w-(--reka-dropdown-menu-trigger-width) overflow-hidden rounded-xl p-0 shadow-lg">
      <DropdownMenuLabel class="bg-primary-soft flex items-center gap-2.5 px-3 py-3 font-normal">
        <img v-if="auth.profile?.avatar_url" :src="auth.profile.avatar_url" alt="" class="size-10 rounded-xl object-cover" />
        <span v-else class="bg-brand-100 text-brand-800 dark:bg-brand-900 dark:text-brand-200 flex size-10 items-center justify-center rounded-xl text-xs font-bold">
          {{ initials }}
        </span>
        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-bold tracking-tight">{{ auth.profile?.full_name }}</p>
          <p class="text-muted-foreground truncate text-[11px]">{{ auth.user?.email }}</p>
        </div>
      </DropdownMenuLabel>

      <div class="p-1.5">
        <DropdownMenuItem class="rounded-md py-2" @select="router.push('/settings/profile')">
          <span class="bg-primary-soft text-primary-text flex size-7 items-center justify-center rounded-md"><UserCog class="size-4" /></span>
          {{ t("shell.profileSettings") }}
        </DropdownMenuItem>
        <div class="flex items-center justify-between gap-2 rounded-md px-2 py-2">
          <span class="flex items-center gap-2 text-sm">
            <SunMoon class="text-primary-text size-4" />
            {{ t("shell.theme") }}
          </span>
          <div role="radiogroup" :aria-label="t('shell.theme')" class="bg-secondary flex gap-0.5 rounded-md p-0.5">
            <button
              v-for="th in themes"
              :key="th.value"
              role="radio"
              :aria-checked="themePref === th.value"
              :aria-label="t(th.label)"
              :title="t(th.label)"
              class="rounded-sm p-1.5 transition-colors"
              :class="themePref === th.value ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'"
              @click="themePref = th.value"
            >
              <component :is="th.icon" class="size-3.5" />
            </button>
          </div>
        </div>
      </div>

      <DropdownMenuSeparator class="my-0" />
      <div class="p-1.5">
        <DropdownMenuItem variant="destructive" class="rounded-md py-2" @select="emit('signOut')">
          <span class="bg-destructive/10 text-destructive flex size-7 items-center justify-center rounded-md"><LogOut class="size-4" /></span>
          {{ t("shell.signOut") }}
        </DropdownMenuItem>
      </div>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
