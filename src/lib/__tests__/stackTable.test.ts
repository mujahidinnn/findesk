import { describe, expect, it } from "vitest";
import { vStack } from "../stackTable";

const cell = (text: string, srOnly = false) => ({
  textContent: text,
  dataset: {} as Record<string, string>,
  querySelector: (sel: string) => (srOnly && sel === ".sr-only" ? { textContent: text } : null),
});

describe("vStack", () => {
  it("labels cells from headers and blanks the sr-only actions column", () => {
    const heads = [cell("Code"), cell("Name"), cell("Actions", true)];
    const row = { cells: [cell("A1"), cell("-"), cell("")] };
    const classes = new Set<string>();
    const table = { classList: { add: (c: string) => classes.add(c) }, tHead: { rows: [{ cells: heads }] }, tBodies: [{ rows: [row] }] };
    (vStack as { mounted: (el: unknown) => void }).mounted(table);
    expect(row.cells.map((c) => c.dataset.label)).toEqual(["Code", "Name", ""]);
    expect(classes.has("table-stack")).toBe(true);
    expect(row.cells.map((c) => "empty" in c.dataset)).toEqual([false, true, true]);
  });
});
