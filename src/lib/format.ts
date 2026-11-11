const qty = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 3 });
const idr = new Intl.NumberFormat("id-ID", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
const fc = new Intl.NumberFormat("id-ID", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const rate = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 6 });

export const formatQty = (value: unknown) => (value == null ? "" : qty.format(Number(value)));

export function formatMoney(value: unknown, currency = "IDR"): string {
  if (value == null || value === "") return "";
  const n = Number(value);
  return currency === "IDR" ? `Rp\u00a0${idr.format(n)}` : `${currency}\u00a0${fc.format(n)}`;
}

export function formatAmount(value: unknown): string {
  if (value == null || value === "") return "";
  const n = Number(value);
  if (n === 0) return "-";
  return n < 0 ? `(${idr.format(-n)})` : idr.format(n);
}

export const formatRate = (value: unknown) => (value == null ? "" : rate.format(Number(value)));

export function formatDate(value: string | null | undefined, withTime = false): string {
  if (!value) return "";
  const d = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T00:00`) : new Date(value);
  return d.toLocaleString("id-ID", withTime ? { dateStyle: "medium", timeStyle: "short" } : { dateStyle: "medium" });
}

export function isoDate(date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

export const monthStart = (d = new Date()) => isoDate(new Date(d.getFullYear(), d.getMonth(), 1));
export const monthEnd = (d = new Date()) => isoDate(new Date(d.getFullYear(), d.getMonth() + 1, 0));
export const yearStart = (d = new Date()) => `${d.getFullYear()}-01-01`;

/** Mirrors the server's round-half-up to 2 decimals, for previews only; the server recomputes every stored amount. */
export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
