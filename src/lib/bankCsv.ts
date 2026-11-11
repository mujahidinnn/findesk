
export interface BankCsvLine {
  line_date: string;
  description: string | null;
  reference: string | null;
  amount: number;
}

const HEADERS: Record<string, string[]> = {
  date: ["date", "tanggal", "tgl", "tanggal transaksi", "transaction date", "posting date", "value date"],
  description: ["description", "keterangan", "deskripsi", "uraian", "remark", "remarks", "narrative"],
  reference: ["reference", "referensi", "ref", "no ref", "no. ref", "nomor referensi", "cheque"],
  amount: ["amount", "jumlah", "nominal", "mutasi", "nilai"],
  debit: ["debit", "db", "debet", "keluar", "withdrawal", "dr"],
  credit: ["credit", "kredit", "cr", "masuk", "deposit"],
};

function splitRow(line: string, delim: string): string[] {
  const out: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quoted) {
      if (c === '"' && line[i + 1] === '"') {
        cell += '"';
        i++;
      }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === delim) {
      out.push(cell.trim());
      cell = "";
    }
    else cell += c;
  }
  out.push(cell.trim());
  return out;
}

export function detectDelimiter(header: string): string {
  const count = (d: string) => splitRow(header, d).length;
  return [";", "\t", ","].reduce((best, d) => (count(d) > count(best) ? d : best), ",");
}

export function parseAmount(raw: string | undefined): number | null {
  if (raw == null) return null;
  let s = raw.trim().replace(/\s|rp|idr|usd/gi, "");
  if (!s) return null;
  const negative = /^\(.*\)$/.test(s) || /^-|-$/.test(s);
  s = s.replace(/^\((.*)\)$/, "$1").replace(/^-|-$/g, "");
  const sign = negative ? -1 : 1;
  if (!/^[\d.,]+$/.test(s)) return null;
  const lastDot = s.lastIndexOf(".");
  const lastComma = s.lastIndexOf(",");
  let decimal: string | null = null;
  if (lastDot >= 0 && lastComma >= 0) decimal = lastDot > lastComma ? "." : ",";
  else if (lastComma >= 0) decimal = s.split(",").length === 2 && s.length - lastComma - 1 <= 2 ? "," : null;
  // A lone dot followed by exactly three digits reads as Indonesian thousands ("1.500" = 1500).
  else if (lastDot >= 0) decimal = s.split(".").length === 2 && s.length - lastDot - 1 !== 3 ? "." : null;
  const [int, frac = ""] = decimal ? [s.slice(0, s.lastIndexOf(decimal)), s.slice(s.lastIndexOf(decimal) + 1)] : [s, ""];
  const n = Number(`${int.replace(/[.,]/g, "")}.${frac || "0"}`);
  return Number.isFinite(n) ? sign * Math.round(n * 100) / 100 : null;
}

export function parseDate(raw: string | undefined): string | null {
  const s = (raw ?? "").trim();
  let y: number, m: number, d: number;
  let hit = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/.exec(s);
  if (hit) [y, m, d] = [Number(hit[1]), Number(hit[2]), Number(hit[3])];
  else if ((hit = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b/.exec(s))) {
    [d, m, y] = [Number(hit[1]), Number(hit[2]), Number(hit[3])];
    if (y < 100) y += 2000;
  } else return null;
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

export function parseBankCsv(text: string): { lines: BankCsvLine[]; skipped: number } {
  const rows = text.replace(/^\uFEFF/, "").split(/\r?\n/).filter((l) => l.trim());
  if (!rows.length) throw new Error("CSV_EMPTY");
  const delim = detectDelimiter(rows[0]);
  const head = splitRow(rows[0], delim).map((h) => h.toLowerCase().replace(/\s+/g, " ").trim());
  const col = (key: string) => head.findIndex((h) => HEADERS[key].includes(h));
  const idx = { date: col("date"), description: col("description"), reference: col("reference"), amount: col("amount"), debit: col("debit"), credit: col("credit") };
  if (idx.date < 0 || (idx.amount < 0 && idx.debit < 0 && idx.credit < 0)) throw new Error("CSV_HEADER");

  const lines: BankCsvLine[] = [];
  let skipped = 0;
  for (const row of rows.slice(1)) {
    const cells = splitRow(row, delim);
    const date = parseDate(cells[idx.date]);
    const amount =
      idx.amount >= 0
        ? parseAmount(cells[idx.amount])
        : (parseAmount(cells[idx.credit]) ?? 0) - Math.abs(parseAmount(cells[idx.debit]) ?? 0);
    if (!date || !amount) {
      skipped++;
      continue;
    }
    const text = (i: number) => (i >= 0 && cells[i] ? cells[i] : null);
    lines.push({ line_date: date, description: text(idx.description), reference: text(idx.reference), amount });
  }
  return { lines, skipped };
}
