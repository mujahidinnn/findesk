import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import { until } from "@vueuse/core";
import { useAuthStore } from "@/stores/auth";
import { i18n } from "@/lib/i18n";
import { NAV_GROUPS, visibleGroups } from "@/lib/navigation";

declare module "vue-router" {
  interface RouteMeta {
    feature?: string;
    public?: boolean;
    superadmin?: boolean;
    title?: string;
    subtitle?: string;
  }
}

const routes: RouteRecordRaw[] = [
  { path: "/login", component: () => import("@/pages/LoginPage.vue"), meta: { public: true } },
  { path: "/reset-password", component: () => import("@/pages/ResetPasswordPage.vue"), meta: { public: true } },
  { path: "/403", component: () => import("@/pages/ForbiddenPage.vue"), meta: { public: true } },
  { path: "/pending", component: () => import("@/components/auth/PendingAccessScreen.vue") },
  { path: "/print/:kind/:id(\\d+)", component: () => import("@/pages/PrintDocPage.vue") },
  {
    path: "/",
    component: () => import("@/components/layout/AppShell.vue"),
    children: [
      {
        path: "",
        component: () => import("@/pages/DashboardPage.vue"),
        meta: { feature: "dashboard", title: "nav.titles.dashboard", subtitle: "nav.descriptions.dashboard" },
      },
      {
        path: "approvals",
        component: () => import("@/pages/ApprovalsPage.vue"),
        meta: { feature: "approval", title: "nav.titles.approvals", subtitle: "nav.descriptions.approvals" },
      },
      {
        path: "accounts",
        component: () => import("@/pages/AccountsPage.vue"),
        meta: { feature: "account", title: "nav.titles.accounts", subtitle: "nav.descriptions.accounts" },
      },
      {
        path: "journals",
        component: () => import("@/pages/JournalsPage.vue"),
        meta: { feature: "journal", title: "nav.titles.journals", subtitle: "nav.descriptions.journals" },
      },
      {
        path: "ledger",
        component: () => import("@/pages/LedgerPage.vue"),
        meta: { feature: "journal", title: "nav.titles.ledger", subtitle: "nav.descriptions.ledger" },
      },
      {
        path: "periods",
        component: () => import("@/pages/PeriodsPage.vue"),
        meta: { feature: "period", title: "nav.titles.periods", subtitle: "nav.descriptions.periods" },
      },
      {
        path: "sales/invoices",
        component: () => import("@/pages/SalesInvoicesPage.vue"),
        meta: { feature: "receivable", title: "nav.titles.invoices", subtitle: "nav.descriptions.invoices" },
      },
      {
        path: "sales/receipts",
        component: () => import("@/pages/ReceiptsPage.vue"),
        meta: { feature: "receivable", title: "nav.titles.receipts", subtitle: "nav.descriptions.receipts" },
      },
      {
        path: "purchases/bills",
        component: () => import("@/pages/BillsPage.vue"),
        meta: { feature: "payable", title: "nav.titles.bills", subtitle: "nav.descriptions.bills" },
      },
      {
        path: "purchases/payments",
        component: () => import("@/pages/VendorPaymentsPage.vue"),
        meta: { feature: "payable", title: "nav.titles.payments", subtitle: "nav.descriptions.payments" },
      },
      {
        path: "partners",
        component: () => import("@/pages/PartnersPage.vue"),
        meta: { feature: "partner", title: "nav.titles.partners", subtitle: "nav.descriptions.partners" },
      },
      {
        path: "aging",
        component: () => import("@/pages/AgingPage.vue"),
        meta: { feature: "reports", title: "nav.titles.aging", subtitle: "nav.descriptions.aging" },
      },
      {
        path: "cash",
        component: () => import("@/pages/CashBankPage.vue"),
        meta: { feature: "cash-bank", title: "nav.titles.cash", subtitle: "nav.descriptions.cash" },
      },
      {
        path: "reconcile",
        component: () => import("@/pages/ReconcilePage.vue"),
        meta: { feature: "reconcile", title: "nav.titles.reconcile", subtitle: "nav.descriptions.reconcile" },
      },
      {
        path: "expenses",
        component: () => import("@/pages/ExpensesPage.vue"),
        meta: { feature: "expense", title: "nav.titles.expenses", subtitle: "nav.descriptions.expenses" },
      },
      {
        path: "tax",
        component: () => import("@/pages/TaxPage.vue"),
        meta: { feature: "tax", title: "nav.titles.tax", subtitle: "nav.descriptions.tax" },
      },
      {
        path: "assets",
        component: () => import("@/pages/AssetsPage.vue"),
        meta: { feature: "asset", title: "nav.titles.assets", subtitle: "nav.descriptions.assets" },
      },
      {
        path: "budgets",
        component: () => import("@/pages/BudgetsPage.vue"),
        meta: { feature: "budget", title: "nav.titles.budgets", subtitle: "nav.descriptions.budgets" },
      },
      {
        path: "reports",
        component: () => import("@/pages/ReportsPage.vue"),
        meta: { feature: "reports", title: "nav.titles.reports", subtitle: "nav.descriptions.reports" },
      },
      {
        path: "audit",
        component: () => import("@/pages/AuditPage.vue"),
        meta: { feature: "audit", title: "nav.titles.audit", subtitle: "nav.descriptions.audit" },
      },
      {
        path: "settings",
        component: () => import("@/pages/SettingsPage.vue"),
        meta: { feature: "settings", title: "nav.titles.settings", subtitle: "nav.descriptions.settings" },
      },
      {
        path: "settings/profile",
        component: () => import("@/pages/ProfileSettingsPage.vue"),
        meta: { title: "profile.title", subtitle: "profile.subtitle" },
      },
      {
        path: "guide",
        component: () => import("@/pages/GuidePage.vue"),
        meta: { title: "nav.titles.guide", subtitle: "nav.descriptions.guide" },
      },
      {
        path: "system",
        component: () => import("@/pages/SystemPage.vue"),
        meta: { superadmin: true, title: "nav.titles.system", subtitle: "nav.descriptions.system" },
      },
    ],
  },
  { path: "/:pathMatch(.*)*", component: () => import("@/pages/NotFound.vue"), meta: { public: true } },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: (to, from, saved) => saved ?? (to.path === from.path ? false : { top: 0 }),
});

router.beforeEach(async (to) => {
  if (to.meta.public) return true;
  const auth = useAuthStore();
  if (!auth.ready) await until(() => auth.ready).toBe(true);
  if (!auth.user) return { path: "/login", query: { redirect: to.fullPath } };
  if (!auth.hasAccess) return to.path === "/pending" ? true : "/pending";
  if (to.path === "/pending") return "/";
  if (to.matched.some((r) => r.meta.superadmin) && !auth.isSuperadmin) return "/403";
  const feature = to.matched.map((r) => r.meta.feature).findLast(Boolean);
  if (feature && !auth.can(feature)) {
    const first = to.path === "/" && visibleGroups(NAV_GROUPS, (f) => auth.can(f), auth.isSuperadmin)[0]?.items[0]?.href;
    return first && first !== "/" ? first : "/403";
  }
  return true;
});

router.afterEach((to) => {
  const key = to.matched.map((r) => r.meta.title).findLast(Boolean);
  document.title = key ? `${i18n.global.t(key)} · FinDesk` : "FinDesk · Keuangan & Akuntansi";
});
