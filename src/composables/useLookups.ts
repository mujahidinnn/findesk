import { computed, toValue, type MaybeRefOrGetter } from "vue";
import { accountName, costCenterName } from "@/lib/accountName";
import { useMasterRows, type MasterRow } from "@/composables/useMasterRows";

const opt = (rows: MasterRow[] | undefined, label: (r: MasterRow) => string) =>
  (rows ?? []).map((r) => ({ value: r.id, label: label(r) }));
const codeName = (r: MasterRow) => `${r.code} · ${r.name}`;

export function useAccountOptions(filter?: MaybeRefOrGetter<{ types?: string[]; subtypes?: string[]; exclude?: string[] } | undefined>) {
  const rows = useMasterRows("m_accounts", { order: "code" });
  const options = computed(() => {
    const f = toValue(filter) ?? {};
    return opt(
      (rows.data.value ?? []).filter(
        (a) =>
          a.is_postable && a.is_active &&
          (!f.types || f.types.includes(String(a.account_type))) &&
          (!f.subtypes || f.subtypes.includes(String(a.subtype))) &&
          (!f.exclude || !f.exclude.includes(String(a.subtype))),
      ),
      (a) => `${a.code} · ${accountName(String(a.code), String(a.name))}`,
    );
  });
  return { rows, options };
}

export function usePartnerOptions(kind: MaybeRefOrGetter<"customer" | "vendor" | undefined>) {
  const rows = useMasterRows("m_partners", { order: "name" });
  const options = computed(() => {
    const k = toValue(kind);
    return opt((rows.data.value ?? []).filter((p) => p.is_active && (!k || (k === "customer" ? p.is_customer : p.is_vendor))), (p) => `${p.name} (${p.code})`);
  });
  return { rows, options };
}

export function useBankOptions(currency?: MaybeRefOrGetter<string | undefined>) {
  const rows = useMasterRows("m_bank_accounts", { order: "code" });
  const options = computed(() => {
    const c = toValue(currency);
    return opt((rows.data.value ?? []).filter((b) => b.is_active && (!c || b.currency === c)), (b) => `${b.name} (${b.currency})`);
  });
  return { rows, options };
}

export function useTaxOptions(kind: "vat" | "wht") {
  const rows = useMasterRows("m_taxes", { order: "code", filter: { kind } });
  return { rows, options: computed(() => opt((rows.data.value ?? []).filter((t) => t.is_active), (t) => String(t.name))) };
}

export function useSimpleOptions(table: "m_cost_centers" | "m_projects" | "m_payment_terms" | "m_items" | "m_asset_categories") {
  const rows = useMasterRows(table, { order: "code" });
  return { rows, options: computed(() => opt((rows.data.value ?? []).filter((r) => r.is_active !== false), table === "m_cost_centers" ? (r) => `${r.code} · ${costCenterName(String(r.code), String(r.name))}` : codeName)) };
}

export function useCurrencyOptions() {
  const rows = useMasterRows("m_currencies" as never, { order: "code" });
  return computed(() =>
    ((rows.data.value ?? []) as unknown as { code: string; name: string; is_active: boolean }[])
      .filter((c) => c.is_active)
      .map((c) => ({ value: c.code, label: `${c.code} · ${c.name}` })),
  );
}

export function usePeriodOptions() {
  const rows = useMasterRows("m_periods", { order: "start_date", descending: true });
  const options = computed(() =>
    (rows.data.value ?? []).map((p) => ({
      value: p.id,
      label: new Date(`${p.start_date}T00:00`).toLocaleDateString("id-ID", { month: "short", year: "numeric" }),
    })),
  );
  return { rows, options };
}
