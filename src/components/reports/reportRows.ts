import { isoDate, round2 } from "@/lib/format";
import { pctChange, type Section, type StatementLine } from "@/lib/statements";

export type Cell = number | string | null;
export type RowKind = "section" | "group" | "header" | "account" | "subtotal" | "total" | "grand";
export interface ReportRow {
  key: string;
  kind: RowKind;
  label: string;
  code?: string;
  accountId?: number | null;
  depth?: number;
  cells?: Cell[];
}

export const pctLabel = (p: number | null) => (p == null ? "" : `${p.toLocaleString("id-ID", { maximumFractionDigits: 1 })}%`);

export const compareCells = (v: number[], compare: boolean): Cell[] =>
  compare ? [v[0], v[1] ?? 0, round2(v[0] - (v[1] ?? 0)), pctLabel(pctChange(v[0], v[1] ?? 0))] : [v[0]];

export const fromLines = (lines: StatementLine[], cells: (v: number[]) => Cell[], totalOf: (name: string) => string, depth = 1): ReportRow[] =>
  lines.map((l) => ({
    key: l.key,
    kind: l.kind,
    label: l.kind === "subtotal" ? totalOf(l.name) : l.name,
    code: l.kind === "account" ? l.code : undefined,
    accountId: l.kind === "account" ? l.accountId : null,
    depth: l.depth + depth,
    cells: l.kind === "header" ? [] : cells(l.values),
  }));

export const exportRows = (rows: ReportRow[], columns: string[], labelCol: string, codeCol: string) =>
  rows.map((r) => ({
    [codeCol]: r.code ?? "",
    [labelCol]: `${"  ".repeat(r.depth ?? 0)}${r.label}`,
    ...Object.fromEntries(columns.map((c, i) => [c, r.cells?.[i] ?? ""])),
  }));

export function groupRows(key: string, label: string, section: Section, cells: (v: number[]) => Cell[], totalLabel: string, totalOf: (name: string) => string, hideEmpty: boolean): ReportRow[] {
  if (hideEmpty && !section.lines.length) return [];
  return [
    { key, kind: "group", label, depth: 0 },
    ...fromLines(section.lines, cells, totalOf),
    { key: `${key}:total`, kind: "total", label: totalLabel, depth: 0, cells: cells(section.total) },
  ];
}

export const addDays = (iso: string, n: number) => {
  const d = new Date(`${iso}T00:00`);
  d.setDate(d.getDate() + n);
  return isoDate(d);
};
export const lastYear = (iso: string) => {
  const [y, m, d] = iso.split("-").map(Number);
  return isoDate(new Date(y - 1, m - 1, Math.min(d, new Date(y - 1, m, 0).getDate())));
};
