import { accountName } from "./accountName";
import { round2 } from "./format";

// Pure statement building: report RPC rows in, grouped lines with subtotals out. Amounts arrive in natural sign
// (assets/expenses debit-positive, the rest credit-positive), so every subtotal is a plain sum.

export interface StatementAccount {
  account_id: number | null;
  code: string;
  name: string;
  account_type: string;
  subtype: string;
  parent_id: number | null;
  is_postable: boolean;
}

export interface StatementLine {
  key: string;
  kind: "header" | "account" | "subtotal";
  code: string;
  name: string;
  accountId: number | null;
  depth: number;
  values: number[];
}

export interface Section {
  key: string;
  lines: StatementLine[];
  total: number[];
}

type Include = (a: StatementAccount) => boolean;

export const keyOf = (a: { account_id: number | null; code: string }) => (a.account_id != null ? String(a.account_id) : a.code);

export const sumCols = (cols: number[][], n = cols[0]?.length ?? 0) =>
  Array.from({ length: n }, (_, i) => round2(cols.reduce((s, c) => s + (c[i] ?? 0), 0)));
const minus = (a: number[], b: number[]) => a.map((v, i) => round2(v - (b[i] ?? 0)));
const plus = (a: number[], b: number[]) => a.map((v, i) => round2(v + (b[i] ?? 0)));
export const isZero = (v: number) => Math.abs(v) < 0.005;

export const pctChange = (now: number, before: number) => (isZero(before) ? null : round2(((now - before) / Math.abs(before)) * 100));

/**
 * One statement section: the postable accounts matching `include`, nested under their chart headers.
 * A header is kept only when every postable account below it belongs to this section and it does not merely
 * repeat the section itself (e.g. "Aset Lancar" under the current-assets section); otherwise its children move up.
 */
export function buildSection(key: string, accounts: StatementAccount[], columns: Map<string, number>[], include: Include, hideZero = false): Section {
  const n = columns.length;
  const byId = new Map(accounts.filter((a) => a.account_id != null).map((a) => [a.account_id!, a]));
  const leaves = accounts.filter((a) => a.is_postable && include(a));
  const inSection = new Set(leaves.map(keyOf));
  const ancestors = (a: StatementAccount) => {
    const out: number[] = [];
    for (let p = a.parent_id; p != null && out.length < 32 && !out.includes(p); p = byId.get(p)?.parent_id ?? null) out.push(p);
    return out;
  };

  const below = new Map<number, StatementAccount[]>();
  for (const a of accounts) if (a.is_postable) for (const p of ancestors(a)) below.set(p, [...(below.get(p) ?? []), a]);
  const kept = new Set(
    [...below].filter(([, d]) => d.length < inSection.size && d.every((a) => inSection.has(keyOf(a)))).map(([id]) => id),
  );

  const children = new Map<number | null, StatementAccount[]>();
  const attach = (a: StatementAccount) => {
    const p = ancestors(a).find((id) => kept.has(id)) ?? null;
    children.set(p, [...(children.get(p) ?? []), a]);
  };
  leaves.forEach(attach);
  kept.forEach((id) => attach(byId.get(id)!));

  const walk = (parent: number | null, depth: number): { lines: StatementLine[]; values: number[] } => {
    const lines: StatementLine[] = [];
    const sums: number[][] = [];
    const kids = [...(children.get(parent) ?? [])].sort((a, b) => a.code.localeCompare(b.code));
    for (const a of kids) {
      const base = { code: a.code, name: accountName(a.code, a.name), accountId: a.account_id, depth };
      if (a.is_postable) {
        const values = columns.map((c) => round2(Number(c.get(keyOf(a)) ?? 0)));
        sums.push(values);
        if (!hideZero || values.some((v) => !isZero(v))) lines.push({ ...base, key: keyOf(a), kind: "account", values });
        continue;
      }
      const sub = walk(a.account_id, depth + 1);
      sums.push(sub.values);
      if (!sub.lines.length) continue;
      lines.push({ ...base, key: `${keyOf(a)}:head`, kind: "header", values: [] }, ...sub.lines);
      lines.push({ ...base, key: `${keyOf(a)}:sum`, kind: "subtotal", values: sub.values });
    }
    return { lines, values: sumCols(sums, n) };
  };
  const { lines, values } = walk(null, 0);
  return { key, lines, total: values };
}

const valueMaps = <R extends StatementAccount>(sets: R[][], value: (r: R) => number) =>
  sets.map((rows) => new Map(rows.map((r) => [keyOf(r), Number(value(r))])));

const CURRENT_ASSET = new Set(["cash", "bank", "receivable", "inventory", "prepaid", "tax_prepaid", "other_current_asset"]);
const BS: { key: string; group: "assets" | "liabilities" | "equity"; include: Include }[] = [
  { key: "currentAssets", group: "assets", include: (a) => a.account_type === "asset" && CURRENT_ASSET.has(a.subtype) },
  { key: "nonCurrentAssets", group: "assets", include: (a) => a.account_type === "asset" && !CURRENT_ASSET.has(a.subtype) },
  { key: "currentLiabilities", group: "liabilities", include: (a) => a.account_type === "liability" && a.subtype !== "long_term_liability" },
  { key: "longTermLiabilities", group: "liabilities", include: (a) => a.account_type === "liability" && a.subtype === "long_term_liability" },
  { key: "equity", group: "equity", include: (a) => a.account_type === "equity" },
];

export type BalanceRow = StatementAccount & { balance: number };

export function balanceSheet(sets: BalanceRow[][], hideZero = false) {
  const cols = valueMaps(sets, (r) => r.balance);
  const sections = BS.map((s) => ({ ...buildSection(s.key, sets[0] ?? [], cols, s.include, hideZero), group: s.group }));
  const total = (g: string) => sumCols(sections.filter((s) => s.group === g).map((s) => s.total), sets.length);
  const assets = total("assets");
  const liabilities = total("liabilities");
  const equity = total("equity");
  const liabilitiesEquity = plus(liabilities, equity);
  return { sections, assets, liabilities, equity, liabilitiesEquity, diff: minus(assets, liabilitiesEquity) };
}

const BELOW_OPEX = ["cogs", "other_expense", "tax_expense"];
const IS: Record<string, Include> = {
  revenue: (a) => a.account_type === "revenue" && a.subtype === "revenue",
  cogs: (a) => a.account_type === "expense" && a.subtype === "cogs",
  opex: (a) => a.account_type === "expense" && !BELOW_OPEX.includes(a.subtype),
  otherIncome: (a) => a.account_type === "revenue" && a.subtype !== "revenue",
  otherExpense: (a) => a.account_type === "expense" && a.subtype === "other_expense",
  tax: (a) => a.account_type === "expense" && a.subtype === "tax_expense",
};

export type AmountRow = StatementAccount & { amount: number };

export function incomeStatement(sets: AmountRow[][], hideZero = false) {
  const cols = valueMaps(sets, (r) => r.amount);
  const s = Object.fromEntries(Object.entries(IS).map(([k, inc]) => [k, buildSection(k, sets[0] ?? [], cols, inc, hideZero)])) as Record<
    keyof typeof IS,
    Section
  >;
  const grossProfit = minus(s.revenue.total, s.cogs.total);
  const operatingProfit = minus(grossProfit, s.opex.total);
  const profitBeforeTax = minus(plus(operatingProfit, s.otherIncome.total), s.otherExpense.total);
  const netIncome = minus(profitBeforeTax, s.tax.total);
  const ledgerNet = sets.map((rows) =>
    round2(rows.filter((r) => r.is_postable).reduce((t, r) => t + (r.account_type === "revenue" ? 1 : -1) * Number(r.amount), 0)),
  );
  return { sections: s, grossProfit, operatingProfit, profitBeforeTax, netIncome, diff: minus(ledgerNet, netIncome) };
}

export interface CashFlowRow {
  section: string;
  account_id: number | null;
  code: string;
  name: string;
  amount: number;
}
export const CASH_SECTIONS = ["operating", "investing", "financing"] as const;

export function cashFlow(rows: CashFlowRow[]) {
  const sections = CASH_SECTIONS.map((key) => {
    const lines = rows
      .filter((r) => r.section === key)
      .sort((a, b) => (a.code === "NI" ? -1 : b.code === "NI" ? 1 : a.code.localeCompare(b.code)))
      .map((r) => ({ ...r, amount: round2(Number(r.amount)) }));
    return { key, lines, total: round2(lines.reduce((s, r) => s + r.amount, 0)) };
  });
  const pick = (k: string) => round2(Number(rows.find((r) => r.section === k)?.amount ?? 0));
  const netChange = round2(sections.reduce((s, x) => s + x.total, 0));
  const opening = pick("cash_opening");
  const closing = pick("cash_closing");
  return { sections, netChange, opening, closing, diff: round2(closing - opening - netChange) };
}

export type TrialRow = StatementAccount & { opening: number; debit: number; credit: number; closing: number };

export function trialBalance(rows: TrialRow[], hideZero = false) {
  const lines = rows
    .filter((r) => r.is_postable)
    .map((r) => ({ ...r, opening: Number(r.opening), debit: Number(r.debit), credit: Number(r.credit), closing: Number(r.closing) }))
    .filter((r) => !hideZero || [r.opening, r.debit, r.credit, r.closing].some((v) => !isZero(v)));
  const sum = (k: "opening" | "debit" | "credit" | "closing") => round2(lines.reduce((s, r) => s + r[k], 0));
  const totals = { opening: sum("opening"), debit: sum("debit"), credit: sum("credit"), closing: sum("closing") };
  const balanced = isZero(totals.debit - totals.credit) && isZero(totals.opening) && isZero(totals.closing);
  return { lines, totals, balanced };
}

export function equityChanges(opening: BalanceRow[], closing: BalanceRow[], netIncome: number, hideZero = false) {
  const eq = (rows: BalanceRow[]) => rows.filter((r) => r.account_type === "equity" && r.is_postable);
  const before = new Map(eq(opening).map((r) => [keyOf(r), Number(r.balance)]));
  const after = new Map(eq(closing).map((r) => [keyOf(r), Number(r.balance)]));
  const accounts = new Map([...eq(opening), ...eq(closing)].map((r) => [keyOf(r), r]));
  const lines = [...accounts.values()]
    .sort((a, b) => a.code.localeCompare(b.code))
    .map((a) => {
      const o = round2(before.get(keyOf(a)) ?? 0);
      const c = round2(after.get(keyOf(a)) ?? 0);
      return { key: keyOf(a), code: a.code, name: accountName(a.code, a.name), accountId: a.account_id, opening: o, movement: round2(c - o), closing: c };
    })
    .filter((l) => !hideZero || !isZero(l.opening) || !isZero(l.closing));
  const sum = (k: "opening" | "movement" | "closing") => round2(lines.reduce((s, l) => s + l[k], 0));
  const totals = { opening: sum("opening"), movement: sum("movement"), closing: sum("closing") };
  return { lines, totals, netIncome: round2(netIncome), other: round2(totals.movement - netIncome) };
}
