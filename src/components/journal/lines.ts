export interface JournalLine {
  account_id: number | null;
  memo: string;
  debit: number | null;
  credit: number | null;
  cost_center_id: number | null;
  project_id: number | null;
}

export const blankLine = (): JournalLine => ({ account_id: null, memo: "", debit: null, credit: null, cost_center_id: null, project_id: null });

export function lineTotals(lines: JournalLine[]) {
  const cents = (v: number | null) => Math.round((v ?? 0) * 100);
  const debit = lines.reduce((s, l) => s + cents(l.debit), 0);
  const credit = lines.reduce((s, l) => s + cents(l.credit), 0);
  return { debit: debit / 100, credit: credit / 100, diff: (debit - credit) / 100 };
}

export const filledLines = (lines: JournalLine[]) =>
  lines
    .filter((l) => l.account_id != null && ((l.debit ?? 0) > 0 || (l.credit ?? 0) > 0))
    .map((l) => ({
      account_id: l.account_id!,
      memo: l.memo.trim() || null,
      debit: l.debit ?? 0,
      credit: l.credit ?? 0,
      cost_center_id: l.cost_center_id,
      project_id: l.project_id,
    }));

export const toLine = (r: Record<string, unknown>): JournalLine => ({
  account_id: r.account_id as number,
  memo: (r.memo as string | null) ?? "",
  debit: Number(r.debit) || null,
  credit: Number(r.credit) || null,
  cost_center_id: (r.cost_center_id as number | null) ?? null,
  project_id: (r.project_id as number | null) ?? null,
});
