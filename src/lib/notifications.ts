export type NotificationTone = "pending" | "approved" | "rejected" | "paid" | "warning" | "neutral";

const KNOWN: Record<string, [key: string, tone: NotificationTone]> = {
  "Jurnal menunggu persetujuan": ["journalPending", "pending"],
  "Jurnal disetujui": ["journalApproved", "approved"],
  "Jurnal ditolak": ["journalRejected", "rejected"],
  "Tagihan pemasok menunggu persetujuan": ["billPending", "pending"],
  "Invoice melewati batas kredit": ["creditLimit", "warning"],
  "Dokumen disetujui": ["docApproved", "approved"],
  "Dokumen ditolak": ["docRejected", "rejected"],
  "Pembayaran menunggu persetujuan": ["paymentPending", "pending"],
  "Pembayaran disetujui": ["paymentApproved", "approved"],
  "Pembayaran ditolak": ["paymentRejected", "rejected"],
  "Pengeluaran kas menunggu persetujuan": ["cashPending", "pending"],
  "Pengeluaran kas disetujui": ["cashApproved", "approved"],
  "Pengeluaran kas ditolak": ["cashRejected", "rejected"],
  "Reimburse menunggu persetujuan": ["expensePending", "pending"],
  "Reimburse disetujui": ["expenseApproved", "approved"],
  "Reimburse ditolak": ["expenseRejected", "rejected"],
  "Reimburse dibayar": ["expensePaid", "paid"],
};

export function describeNotification(title: string): { key: string | null; tone: NotificationTone } {
  const k = KNOWN[title];
  return k ? { key: k[0], tone: k[1] } : { key: null, tone: "neutral" };
}
