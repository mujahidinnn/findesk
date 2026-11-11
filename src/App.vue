<script setup lang="ts">
import { useColorMode, useMediaQuery } from "@vueuse/core";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import "vue-sonner/style.css";

const mode = useColorMode();
const phone = useMediaQuery("(width < 40rem)");
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <RouterView />
  </TooltipProvider>
  <Toaster :theme="mode === 'dark' ? 'dark' : 'light'" :position="phone ? 'top-center' : 'bottom-right'" rich-colors />
</template>
