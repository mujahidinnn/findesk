import { createApp } from "vue";
import { createPinia } from "pinia";
import { MutationCache, QueryCache, QueryClient, VueQueryPlugin } from "@tanstack/vue-query";
import App from "./App.vue";
import { router } from "./router";
import { i18n } from "./lib/i18n";
import { logClientError } from "./lib/errorLog";
import { vStack } from "./lib/stackTable";
import { useAuthStore } from "./stores/auth";
import "./style.css";

const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (e, query) => logClientError("query", e.message, { key: JSON.stringify(query.queryKey) }),
  }),
  mutationCache: new MutationCache({
    onError: (e, _vars, _ctx, mutation) =>
      logClientError("mutation", e.message, { key: JSON.stringify(mutation.options.mutationKey ?? null) }),
  }),
  defaultOptions: { queries: { staleTime: 30_000, retry: 1 } },
});

const app = createApp(App);
app.directive("stack", vStack);
app.config.errorHandler = (err, _instance, info) => {
  console.error(err);
  logClientError("vue", err instanceof Error ? err.message : String(err), { info });
};
app.use(createPinia()).use(i18n).use(VueQueryPlugin, { queryClient });
useAuthStore().init();
app.use(router);

router.isReady().then(() => {
  app.mount("#app");
  const splash = document.getElementById("splash");
  if (splash) {
    splash.style.transition = "opacity 0.3s ease";
    splash.style.opacity = "0";
    setTimeout(() => splash.remove(), 300);
  }
});
