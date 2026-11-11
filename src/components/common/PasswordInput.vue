<script setup lang="ts">
import type { HTMLAttributes } from "vue";
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { Eye, EyeOff } from "@lucide/vue";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

defineOptions({ inheritAttrs: false });
const model = defineModel<string>({ required: true });
const props = defineProps<{ class?: HTMLAttributes["class"] }>();
const { t } = useI18n();
const show = ref(false);
</script>

<template>
  <div class="relative">
    <Input v-model="model" v-bind="$attrs" :type="show ? 'text' : 'password'" :class="cn('pr-10', props.class)" />
    <button
      type="button"
      class="text-muted-foreground hover:text-foreground absolute top-1/2 right-3 -translate-y-1/2"
      :aria-label="t(show ? 'login.hidePassword' : 'login.showPassword')"
      :aria-pressed="show"
      @click="show = !show"
    >
      <component :is="show ? EyeOff : Eye" class="size-4" />
    </button>
  </div>
</template>
