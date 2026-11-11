import { describe, expect, it } from "vitest";
import { formatAmount, formatMoney, round2 } from "../format";

describe("format", () => {
  it("shows money per currency", () => {
    expect(formatMoney(1250000)).toBe("Rp\u00a01.250.000");
    expect(formatMoney(1250.5, "USD")).toBe("USD\u00a01.250,50");
  });
  it("uses accounting brackets for negatives", () => {
    expect(formatAmount(-1500)).toBe("(1.500)");
    expect(formatAmount(0)).toBe("-");
  });
  it("rounds half up", () => {
    expect(round2(1.005)).toBe(1.01);
    expect(round2(9166666.666)).toBe(9166666.67);
  });
});
