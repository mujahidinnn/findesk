import { describe, expect, it } from "vitest";
import { toCsv, toSpreadsheetXml } from "../csv";

describe("export formats", () => {
  it("quotes CSV cells that contain commas or quotes", () => {
    expect(toCsv([{ a: 'x,"y"', b: 1 }])).toBe('a,b\n"x,""y""",1');
  });
  it("writes numbers as numbers and keeps leading-zero codes as text in Excel XML", () => {
    const out = toSpreadsheetXml([{ qty: 12, price: "1500.50", phone: "0812", name: "A & B" }], "Sheet");
    expect(out).toContain('<Data ss:Type="Number">12</Data>');
    expect(out).toContain('<Data ss:Type="Number">1500.5</Data>');
    expect(out).toContain('<Data ss:Type="String">0812</Data>');
    expect(out).toContain("A &amp; B");
  });
});
