import { describe, expect, it } from "vitest";
import { ref } from "vue";
import { rowText, usePaged } from "@/composables/usePaged";

describe("usePaged", () => {
  it("windows the list and clamps the last page", () => {
    const list = ref(Array.from({ length: 23 }, (_, i) => i));
    const p = usePaged(list);
    expect(p.pages.value).toBe(3);
    p.page.value = 3;
    expect(p.rows.value).toEqual([20, 21, 22]);
  });
  it("searches joined objects one level deep", () => {
    expect(rowText({ doc_no: "INV-1", customer: { name: "Budi" }, n: null })).toContain("budi");
  });
});
