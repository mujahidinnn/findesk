import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";

export function useTabParam<T extends string>(tabs: () => readonly T[]) {
  const route = useRoute();
  const router = useRouter();
  return computed<T | undefined>({
    get: () => tabs().find((x) => x === route.query.tab) ?? tabs()[0],
    set: (tab) => void router.replace({ query: { ...route.query, tab } }),
  });
}
