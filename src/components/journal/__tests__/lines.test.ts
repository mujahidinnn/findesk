import { describe, expect, it } from "vitest";
import { blankLine, filledLines, lineTotals } from "../lines";

describe("journal lines", () => {
  it("balances in cents and keeps only filled lines", () => {
    const lines = [
      { ...blankLine(), account_id: 1, debit: 0.1 },
      { ...blankLine(), account_id: 2, debit: 0.2 },
      { ...blankLine(), account_id: 3, credit: 0.3, memo: " x " },
      { ...blankLine(), account_id: 4 },
      { ...blankLine(), credit: 5 },
    ];
    expect(lineTotals(lines.slice(0, 3))).toEqual({ debit: 0.3, credit: 0.3, diff: 0 });
    expect(lineTotals(lines).diff).toBe(-5);
    const kept = filledLines(lines);
    expect(kept).toHaveLength(3);
    expect(kept[2]).toMatchObject({ account_id: 3, debit: 0, credit: 0.3, memo: "x" });
  });
});
