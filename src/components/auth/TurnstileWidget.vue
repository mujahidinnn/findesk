<script lang="ts">
type Turnstile = {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  reset: (id: string) => void;
  remove: (id: string) => void;
};
declare global {
  interface Window {
    turnstile?: Turnstile;
  }
}

const SITE_KEY = import.meta.env.VITE_TURNSTILE_SITE_KEY;
export const captchaRequired = !!SITE_KEY;

let loader: Promise<Turnstile> | undefined;
function loadTurnstile() {
  return (loader ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    s.async = true;
    s.onload = () => resolve(window.turnstile!);
    s.onerror = () => {
      loader = undefined;
      reject(new Error("turnstile failed to load"));
    };
    document.head.append(s);
  }));
}
</script>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { useI18n } from "vue-i18n";

// Tokens are single use: callers reset() after every auth request.
const token = defineModel<string>({ default: "" });
const { locale } = useI18n();
const el = ref<HTMLElement>();
let widgetId: string | undefined;

onMounted(async () => {
  if (!SITE_KEY || !el.value) return;
  const ts = await loadTurnstile().catch(() => undefined);
  if (!ts || !el.value) return;
  widgetId = ts.render(el.value, {
    sitekey: SITE_KEY,
    theme: "auto",
    language: locale.value,
    callback: (t: string) => (token.value = t),
    "expired-callback": () => (token.value = ""),
    "error-callback": () => (token.value = ""),
  });
});
onBeforeUnmount(() => widgetId && window.turnstile?.remove(widgetId));

defineExpose({
  reset() {
    token.value = "";
    if (widgetId) window.turnstile?.reset(widgetId);
  },
});
</script>

<template>
  <div v-if="captchaRequired" ref="el" class="flex min-h-[65px] justify-center" />
</template>
