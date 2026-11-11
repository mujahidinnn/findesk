<script setup lang="ts" generic="T extends string">
import type { Component } from "vue";
import { Building2, History, UserCog } from "@lucide/vue";
import { cn } from "@/lib/utils";

const ICONS: Record<string, Component> = { company: Building2, users: UserCog, history: History };

defineProps<{ tabs: { key: T; label: string; icon?: Component }[] }>();
const active = defineModel<T | undefined>({ required: true });
</script>

<template>
  <div class="border-b" role="tablist">
    <div class="-mb-px flex gap-1 overflow-x-auto">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        role="tab"
        :aria-selected="active === tab.key"
        :class="
          cn(
            'flex items-center gap-1.5 border-b-2 px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors',
            active === tab.key
              ? 'border-primary text-primary-text'
              : 'text-muted-foreground hover:text-foreground border-transparent',
          )
        "
        @click="active = tab.key"
      >
        <component :is="tab.icon ?? ICONS[tab.key]" v-if="tab.icon ?? ICONS[tab.key]" class="size-4" />
        {{ tab.label }}
      </button>
    </div>
  </div>
</template>
