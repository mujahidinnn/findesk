import { computed, ref, watch, type MaybeRefOrGetter, toValue } from "vue";

export function rowText(row: Record<string, unknown>): string {
  const out: string[] = [];
  for (const v of Object.values(row)) {
    if (v == null) continue;
    if (typeof v !== "object") out.push(String(v));
    else for (const w of Object.values(v as Record<string, unknown>)) if (w != null && typeof w !== "object") out.push(String(w));
  }
  return out.join(" ").toLowerCase();
}

export function usePaged<T>(list: MaybeRefOrGetter<T[]>, perPageDefault = 10) {
  const page = ref(1);
  const perPage = ref(perPageDefault);
  const total = computed(() => toValue(list).length);
  const pages = computed(() => Math.max(1, Math.ceil(total.value / perPage.value)));
  const rows = computed(() => toValue(list).slice((page.value - 1) * perPage.value, page.value * perPage.value));
  watch([total, perPage], () => (page.value = 1));
  return { page, perPage, total, pages, rows };
}

export function useLoadMore<T>(list: MaybeRefOrGetter<T[]>, step = 10) {
  const shown = ref(step);
  const total = computed(() => toValue(list).length);
  const rows = computed(() => toValue(list).slice(0, shown.value));
  const more = computed(() => Math.max(0, total.value - shown.value));
  watch(total, () => (shown.value = step));
  return { rows, total, more, loadMore: () => (shown.value += step) };
}
