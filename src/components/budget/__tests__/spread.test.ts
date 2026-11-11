import { describe, expect, it } from "vitest";
import { spreadEvenly } from "../spread";

describe("spreadEvenly", () => {
  it("keeps the annual total exact", () => {
    const months = spreadEvenly(1_000_000);
    expect(months).toHaveLength(12);
    expect(months.slice(0, 11).every((m) => m === 83_333)).toBe(true);
    expect(months[11]).toBe(83_337);
    expect(months.reduce((a, b) => a + b, 0)).toBe(1_000_000);
  });
  it("handles zero and negatives", () => {
    expect(spreadEvenly(0)).toEqual(Array(12).fill(0));
    expect(spreadEvenly(-120).reduce((a, b) => a + b, 0)).toBe(-120);
  });
});
