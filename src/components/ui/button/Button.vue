<script setup lang="ts">
import type { PrimitiveProps } from "reka-ui"
import type { HTMLAttributes } from "vue"
import type { ButtonVariants } from "."
import { computed, useAttrs } from "vue"
import { LoaderCircle } from "@lucide/vue"
import { Primitive } from "reka-ui"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { cn } from "@/lib/utils"
import { buttonVariants } from "."

interface Props extends PrimitiveProps {
  variant?: ButtonVariants["variant"]
  size?: ButtonVariants["size"]
  class?: HTMLAttributes["class"]
  loading?: boolean
  tooltip?: string
}

defineOptions({ inheritAttrs: false })
const props = withDefaults(defineProps<Props>(), {
  as: "button",
})
const attrs = useAttrs()
const disabled = computed(() => props.loading || ("disabled" in attrs && attrs.disabled !== false) || undefined)
</script>

<template>
  <Tooltip v-if="tooltip">
    <TooltipTrigger as-child>
      <Primitive
        v-bind="attrs"
        data-slot="button"
        :data-variant="variant"
        :data-size="size"
        :as="as"
        :as-child="asChild"
        :disabled="disabled"
        :aria-busy="loading || undefined"
        :aria-label="(attrs['aria-label'] as string | undefined) ?? tooltip"
        :class="cn(buttonVariants({ variant, size }), loading && '[&>svg:not(.animate-spin)]:hidden', props.class)"
      >
        <LoaderCircle v-if="loading" class="animate-spin" />
        <slot />
      </Primitive>
    </TooltipTrigger>
    <TooltipContent>{{ tooltip }}</TooltipContent>
  </Tooltip>
  <Primitive
    v-else
    v-bind="attrs"
    data-slot="button"
    :data-variant="variant"
    :data-size="size"
    :as="as"
    :as-child="asChild"
    :disabled="disabled"
    :aria-busy="loading || undefined"
    :aria-label="(attrs['aria-label'] as string | undefined) ?? tooltip"
    :class="cn(buttonVariants({ variant, size }), loading && '[&>svg:not(.animate-spin)]:hidden', props.class)"
  >
    <LoaderCircle v-if="loading" class="animate-spin" />
    <slot />
  </Primitive>
</template>
