import type { Component } from "vue";
import {
  BookOpen, Building2, CalendarCheck, ChartColumn, Compass, DatabaseZap, FileInput, GitCompareArrows, History, Hourglass,
  Landmark, LayoutDashboard, ListTree, Percent, Receipt, ScrollText, Settings, ShieldCheck, Target, Users, Wallet,
  BanknoteArrowDown, BanknoteArrowUp,
} from "@lucide/vue";

export interface NavItem {
  href: string;
  key: string;
  icon: Component;
  featureKey?: string;
  superadminOnly?: boolean;
}

export interface NavGroup {
  key: string;
  items: NavItem[];
}

export const NAV_GROUPS: NavGroup[] = [
  {
    key: "overview",
    items: [
      { href: "/", key: "dashboard", icon: LayoutDashboard, featureKey: "dashboard" },
      { href: "/approvals", key: "approvals", icon: ShieldCheck, featureKey: "approval" },
    ],
  },
  {
    key: "master",
    items: [
      { href: "/partners", key: "partners", icon: Users, featureKey: "partner" },
      { href: "/accounts", key: "accounts", icon: ListTree, featureKey: "account" },
    ],
  },
  {
    key: "sales",
    items: [
      { href: "/sales/invoices", key: "invoices", icon: Receipt, featureKey: "receivable" },
      { href: "/sales/receipts", key: "receipts", icon: BanknoteArrowDown, featureKey: "receivable" },
    ],
  },
  {
    key: "purchases",
    items: [
      { href: "/purchases/bills", key: "bills", icon: FileInput, featureKey: "payable" },
      { href: "/purchases/payments", key: "payments", icon: BanknoteArrowUp, featureKey: "payable" },
      { href: "/expenses", key: "expenses", icon: Wallet, featureKey: "expense" },
    ],
  },
  {
    key: "treasury",
    items: [
      { href: "/cash", key: "cash", icon: Landmark, featureKey: "cash-bank" },
      { href: "/reconcile", key: "reconcile", icon: GitCompareArrows, featureKey: "reconcile" },
    ],
  },
  {
    key: "accounting",
    items: [
      { href: "/journals", key: "journals", icon: BookOpen, featureKey: "journal" },
      { href: "/ledger", key: "ledger", icon: ScrollText, featureKey: "journal" },
      { href: "/periods", key: "periods", icon: CalendarCheck, featureKey: "period" },
    ],
  },
  {
    key: "compliance",
    items: [
      { href: "/tax", key: "tax", icon: Percent, featureKey: "tax" },
      { href: "/assets", key: "assets", icon: Building2, featureKey: "asset" },
    ],
  },
  {
    key: "insight",
    items: [
      { href: "/reports", key: "reports", icon: ChartColumn, featureKey: "reports" },
      { href: "/aging", key: "aging", icon: Hourglass, featureKey: "reports" },
      { href: "/budgets", key: "budgets", icon: Target, featureKey: "budget" },
      { href: "/audit", key: "audit", icon: History, featureKey: "audit" },
    ],
  },
  {
    key: "settings",
    items: [
      { href: "/settings", key: "settings", icon: Settings, featureKey: "settings" },
      { href: "/system", key: "system", icon: DatabaseZap, superadminOnly: true },
    ],
  },
  {
    key: "help",
    items: [{ href: "/guide", key: "guide", icon: Compass }],
  },
];

export function visibleGroups(
  groups: NavGroup[],
  canRead: (feature: string) => boolean,
  isSuperadmin: boolean,
): NavGroup[] {
  return groups
    .map((g) => ({
      ...g,
      items: g.items.filter((i) => (i.superadminOnly ? isSuperadmin : !i.featureKey || canRead(i.featureKey))),
    }))
    .filter((g) => g.items.length > 0);
}
