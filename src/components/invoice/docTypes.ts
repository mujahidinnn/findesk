export type Side = "sales" | "purchase";
export type DocType = "sales_invoice" | "sales_credit" | "purchase_bill" | "purchase_debit";
export type Direction = "in" | "out";

export const sideOf = (d: string): Side => (d.startsWith("sales") ? "sales" : "purchase");
export const featureOf = (d: string) => (d.startsWith("sales") || d === "in" ? "receivable" : "payable");
export const isNote = (d: string) => d === "sales_credit" || d === "purchase_debit";
export const noteTarget = (d: string): DocType => (d.startsWith("sales") ? "sales_invoice" : "purchase_bill");
/** Receipts settle sales invoices and supplier refunds (debit notes); payments the opposite. Mirrors payment_target_ok. */
export const PAYMENT_TARGETS: Record<Direction, DocType[]> = {
  in: ["sales_invoice", "purchase_debit"],
  out: ["purchase_bill", "sales_credit"],
};
export const directionFor = (d: string): Direction => (d === "sales_invoice" || d === "purchase_debit" ? "in" : "out");

export const openOf = (r: Record<string, unknown>) => Number(r.total ?? 0) - Number(r.paid_amount ?? 0);
export const docLabel = (r: Record<string, unknown> & { id: number }) => (r.doc_no ? String(r.doc_no) : `Draft #${r.id}`);
export const nameOf = (v: unknown) => (v as { name?: string } | null)?.name ?? "";

export interface InvoiceLine {
  item_id: number | null;
  account_id: number | null;
  description: string;
  qty: number | null;
  unit_price: number | null;
  discount: number | null;
  tax_id: number | null;
  wht_tax_id: number | null;
}
export const blankLine = (): InvoiceLine => ({
  item_id: null, account_id: null, description: "", qty: 1, unit_price: null, discount: null, tax_id: null, wht_tax_id: null,
});
