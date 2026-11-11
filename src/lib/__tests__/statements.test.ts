import { describe, expect, it } from "vitest";
import { balanceSheet, cashFlow, equityChanges, incomeStatement, pctChange, trialBalance, type AmountRow, type BalanceRow } from "../statements";

const acc = (account_id: number | null, code: string, account_type: string, subtype: string, parent_id: number | null, is_postable = true) => ({
  account_id, code, name: `A${code}`, account_type, subtype, parent_id, is_postable,
});
const CHART = [
  acc(1, "1", "asset", "other_current_asset", null, false),
  acc(2, "1100", "asset", "other_current_asset", 1, false),
  acc(3, "1110", "asset", "cash", 2, false),
  acc(4, "1111", "asset", "cash", 3),
  acc(5, "1112", "asset", "cash", 3),
  acc(10, "1130", "asset", "receivable", 2),
  acc(19, "1200", "asset", "fixed_asset", 1, false),
  acc(23, "1230", "asset", "fixed_asset", 19),
  acc(24, "1231", "asset", "accumulated_depreciation", 19),
  acc(27, "2", "liability", "other_current_liability", null, false),
  acc(29, "2110", "liability", "payable", 27),
  acc(40, "2210", "liability", "long_term_liability", 27),
  acc(41, "3", "equity", "equity", null, false),
  acc(42, "3100", "equity", "equity", 41),
  acc(null, "CYE", "equity", "retained_earnings", 41),
];
const bs = (bal: Record<string, number>): BalanceRow[] => CHART.map((a) => ({ ...a, balance: bal[a.code] ?? 0 }));

describe("balance sheet", () => {
  const now = bs({ "1111": 100, "1112": 50, "1130": 200, "1230": 400, "1231": -100, "2110": 150, "2210": 300, "3100": 150, CYE: 50 });
  const before = bs({ "1111": 80, "1130": 20, "2110": 0, "3100": 100 });

  it("splits sections, keeps only sub-headers, and ties out", () => {
    const r = balanceSheet([now, before]);
    const current = r.sections.find((s) => s.key === "currentAssets")!;
    expect(current.lines.map((l) => `${l.kind}:${l.code}`)).toEqual(["header:1110", "account:1111", "account:1112", "subtotal:1110", "account:1130"]);
    expect(current.lines[3].values).toEqual([150, 80]);
    expect(current.total).toEqual([350, 100]);
    expect(r.sections.find((s) => s.key === "nonCurrentAssets")!.total).toEqual([300, 0]);
    expect(r.assets).toEqual([650, 100]);
    expect(r.liabilities).toEqual([450, 0]);
    expect(r.equity).toEqual([200, 100]);
    expect(r.diff).toEqual([0, 0]);
  });

  it("hides zero rows and empty headers", () => {
    const r = balanceSheet([bs({ "1130": 10, "3100": 10 })], true);
    expect(r.sections.find((s) => s.key === "currentAssets")!.lines.map((l) => l.code)).toEqual(["1130"]);
    expect(r.sections.find((s) => s.key === "equity")!.lines.map((l) => l.code)).toEqual(["3100"]);
  });

  it("reports an imbalance", () => {
    expect(balanceSheet([bs({ "1111": 10 })]).diff).toEqual([10]);
  });
});

describe("income statement", () => {
  const rows = (amt: Record<string, number>): AmountRow[] =>
    [
      acc(60, "4100", "revenue", "revenue", null),
      acc(61, "5100", "expense", "cogs", null),
      acc(62, "6100", "expense", "expense", null),
      acc(63, "6200", "expense", "depreciation", null),
      acc(64, "7100", "revenue", "other_income", null),
      acc(65, "8100", "expense", "other_expense", null),
      acc(66, "9100", "expense", "tax_expense", null),
    ].map((a) => ({ ...a, amount: amt[a.code] ?? 0 }));

  it("computes the multi-step subtotals", () => {
    const r = incomeStatement([rows({ "4100": 1000, "5100": 600, "6100": 150, "6200": 50, "7100": 20, "8100": 10, "9100": 42 })]);
    expect(r.grossProfit).toEqual([400]);
    expect(r.operatingProfit).toEqual([200]);
    expect(r.profitBeforeTax).toEqual([210]);
    expect(r.netIncome).toEqual([168]);
    expect(r.diff).toEqual([0]);
  });
});

describe("cash flow", () => {
  it("reconciles opening + net change to closing", () => {
    const r = cashFlow([
      { section: "operating", account_id: 10, code: "1130", name: "AR", amount: -30 },
      { section: "operating", account_id: null, code: "NI", name: "NI", amount: 100 },
      { section: "investing", account_id: 23, code: "1230", name: "Car", amount: -50 },
      { section: "financing", account_id: 40, code: "2210", name: "Loan", amount: 10 },
      { section: "cash_opening", account_id: null, code: "CASH0", name: "o", amount: 500 },
      { section: "cash_closing", account_id: null, code: "CASH1", name: "c", amount: 530 },
    ]);
    expect(r.sections[0].lines[0].code).toBe("NI");
    expect(r.sections.map((s) => s.total)).toEqual([70, -50, 10]);
    expect(r.netChange).toBe(30);
    expect(r.diff).toBe(0);
  });
});

describe("trial balance", () => {
  it("checks debits equal credits", () => {
    const t = (code: string, opening: number, debit: number, credit: number) => ({
      ...acc(Number(code), code, "asset", "cash", null), opening, debit, credit, closing: opening + debit - credit,
    });
    const r = trialBalance([t("1", 100, 50, 0), t("2", -100, 0, 50), t("3", 0, 0, 0)], true);
    expect(r.lines).toHaveLength(2);
    expect(r.totals).toEqual({ opening: 0, debit: 50, credit: 50, closing: 0 });
    expect(r.balanced).toBe(true);
    expect(trialBalance([t("1", 0, 10, 0)]).balanced).toBe(false);
  });
});

describe("equity changes", () => {
  it("splits movement into net income and other changes", () => {
    const r = equityChanges(bs({ "3100": 100, CYE: 20 }), bs({ "3100": 150, CYE: 50 }), 30);
    expect(r.lines.map((l) => [l.code, l.opening, l.movement, l.closing])).toEqual([
      ["3100", 100, 50, 150],
      ["CYE", 20, 30, 50],
    ]);
    expect(r.totals.movement).toBe(80);
    expect(r.other).toBe(50);
  });
});

it("percent change", () => {
  expect(pctChange(150, 100)).toBe(50);
  expect(pctChange(-50, -100)).toBe(50);
  expect(pctChange(10, 0)).toBeNull();
});
