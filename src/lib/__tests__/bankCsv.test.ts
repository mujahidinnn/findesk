import { describe, expect, it } from "vitest";
import { detectDelimiter, parseAmount, parseBankCsv, parseDate } from "../bankCsv";

describe("parseAmount", () => {
  it.each([
    ["1.234.567,89", 1234567.89],
    ["1,234,567.89", 1234567.89],
    ["1.500", 1500],
    ["1500.5", 1500.5],
    ["2,5", 2.5],
    ["1,000,000", 1000000],
    ["-250.000", -250000],
    ["(1.000)", -1000],
    ["75.000-", -75000],
    ["Rp 2.500", 2500],
    ["", null],
    ["abc", null],
  ])("%s → %s", (raw, expected) => expect(parseAmount(raw)).toBe(expected));
});

describe("parseDate", () => {
  it.each([
    ["2026-10-05", "2026-10-05"],
    ["05/10/2026", "2026-10-05"],
    ["5-10-26", "2026-10-05"],
    ["05.10.2026", "2026-10-05"],
    ["31/02/2026", null],
    ["kemarin", null],
  ])("%s → %s", (raw, expected) => expect(parseDate(raw)).toBe(expected));
});

describe("parseBankCsv", () => {
  it("detects the delimiter", () => {
    expect(detectDelimiter("tanggal;keterangan;jumlah")).toBe(";");
    expect(detectDelimiter("date,description,amount")).toBe(",");
  });

  it("reads a signed amount column with Indonesian numbers", () => {
    const csv = '﻿Tanggal;Keterangan;Referensi;Jumlah\r\n01/10/2026;"Setoran; tunai";TRF01;1.250.000,00\r\n02/10/2026;Biaya admin;;-15.000\r\n\r\n';
    expect(parseBankCsv(csv)).toEqual({
      lines: [
        { line_date: "2026-10-01", description: "Setoran; tunai", reference: "TRF01", amount: 1250000 },
        { line_date: "2026-10-02", description: "Biaya admin", reference: null, amount: -15000 },
      ],
      skipped: 0,
    });
  });

  it("turns debit/credit columns into a signed amount and skips unreadable rows", () => {
    const csv = "date,description,debit,credit\n2026-10-03,Fee,\"2,500.00\",\n2026-10-04,Transfer in,,\"1,000,000.00\"\nTotal,,,\n";
    const { lines, skipped } = parseBankCsv(csv);
    expect(lines.map((l) => l.amount)).toEqual([-2500, 1000000]);
    expect(skipped).toBe(1);
  });

  it("refuses a file without date or amount columns", () => {
    expect(() => parseBankCsv("foo,bar\n1,2")).toThrow("CSV_HEADER");
    expect(() => parseBankCsv("")).toThrow("CSV_EMPTY");
  });
});
