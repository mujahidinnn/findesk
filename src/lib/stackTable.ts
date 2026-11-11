import type { Directive } from "vue";

function label(table: HTMLTableElement) {
  table.classList.add("table-stack");
  const heads = [...(table.tHead?.rows[0]?.cells ?? [])].map((c) =>
    c.querySelector(".sr-only") && c.textContent?.trim() === c.querySelector(".sr-only")?.textContent?.trim() ? "" : (c.textContent?.trim() ?? ""),
  );
  for (const body of table.tBodies)
    for (const row of body.rows)
      [...row.cells].forEach((c, i) => {
        c.dataset.label = heads[i] ?? "";
        const empty = /^[-—]?$/.test(c.textContent?.trim() ?? "") && !c.querySelector("img, input, button, [role=combobox]");
        if (empty) c.dataset.empty = "";
        else delete c.dataset.empty;
      });
}

function align(table: HTMLTableElement) {
  const heads = [...(table.tHead?.rows[0]?.cells ?? [])];
  for (const body of table.tBodies)
    for (const row of body.rows)
      [...row.cells].forEach((c, i) => {
        for (const cls of ["text-right", "text-center"]) if (c.classList?.contains(cls)) heads[i]?.classList.add(cls);
      });
}

function apply(table: HTMLTableElement) {
  label(table);
  align(table);
}

export const vStack: Directive<HTMLTableElement> = { mounted: apply, updated: apply };

declare module "vue" {
  interface GlobalDirectives {
    vStack: typeof vStack;
  }
}
