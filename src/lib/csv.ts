import { isoDate } from "./format";

export type ExportFormat = "csv" | "xls" | "json" | "pdf";
type Row = Record<string, unknown>;

export function toCsv(rows: Row[]): string {
  if (!rows.length) return "";
  const cols = Object.keys(rows[0]);
  const esc = (v: unknown) => {
    const s = v == null ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
  };
  return [cols.join(","), ...rows.map((r) => cols.map((c) => esc(r[c])).join(","))].join("\n");
}

const xml = (v: unknown) => String(v ?? "").replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" })[c]!);
const isNum = (v: unknown) => typeof v === "number" || (typeof v === "string" && /^-?(0|[1-9]\d*)(\.\d+)?$/.test(v));

// ponytail: SpreadsheetML, not .xlsx (that needs a zip writer); Excel shows a format notice on open. Add a library if that matters.
export function toSpreadsheetXml(rows: Row[], sheet: string): string {
  const cols = Object.keys(rows[0] ?? {});
  const cell = (v: unknown) => (isNum(v) ? `<Cell><Data ss:Type="Number">${Number(v)}</Data></Cell>` : `<Cell><Data ss:Type="String">${xml(v)}</Data></Cell>`);
  const head = `<Row>${cols.map((c) => `<Cell ss:StyleID="h"><Data ss:Type="String">${xml(c)}</Data></Cell>`).join("")}</Row>`;
  return `<?xml version="1.0"?><?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles><Style ss:ID="h"><Font ss:Bold="1"/><Interior ss:Color="#FDE8B0" ss:Pattern="Solid"/></Style></Styles>
<Worksheet ss:Name="${xml(sheet.slice(0, 31))}"><Table>${head}${rows.map((r) => `<Row>${cols.map((c) => cell(r[c])).join("")}</Row>`).join("")}</Table></Worksheet>
</Workbook>`;
}

function printTable(rows: Row[], title: string) {
  const cols = Object.keys(rows[0] ?? {});
  const w = window.open("", "_blank");
  if (!w) throw new Error("popup blocked");
  w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${xml(title)}</title><style>
body{font:11px/1.4 "DM Sans",system-ui,sans-serif;margin:24px;color:#1c1917}
h1{font-size:16px;margin:0 0 4px}p{color:#78716c;margin:0 0 16px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #e7e5e4;padding:4px 6px;text-align:left}
th{background:#fde8b0}td.n{text-align:right;font-variant-numeric:tabular-nums}
@page{size:A4 landscape;margin:12mm}</style></head><body>
<h1>${xml(title)}</h1><p>FinDesk · ${isoDate()} · ${rows.length} rows</p>
<table><thead><tr>${cols.map((c) => `<th>${xml(c)}</th>`).join("")}</tr></thead><tbody>
${rows.map((r) => `<tr>${cols.map((c) => `<td${isNum(r[c]) ? ' class="n"' : ""}>${xml(r[c])}</td>`).join("")}</tr>`).join("")}
</tbody></table><script>window.onload=()=>{window.print()}</script></body></html>`);
  w.document.close();
}

function save(blob: Blob, name: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  URL.revokeObjectURL(a.href);
}

export function downloadRows(key: string, rows: Row[], format: ExportFormat = "csv", title = key) {
  const name = `findesk-${key}-${isoDate()}`;
  if (format === "csv") return save(new Blob(["﻿" + toCsv(rows)], { type: "text/csv;charset=utf-8" }), `${name}.csv`);
  if (format === "xls") return save(new Blob([toSpreadsheetXml(rows, title)], { type: "application/vnd.ms-excel" }), `${name}.xls`);
  if (format === "json") return save(new Blob([JSON.stringify(rows, null, 2)], { type: "application/json" }), `${name}.json`);
  printTable(rows, title);
}

export const downloadCsv = (key: string, rows: Row[]) => downloadRows(key, rows, "csv");
