# FinDesk Guideline

FinDesk is the finance module of the porto ERP family (WorkDesk = HR/payroll, StockDesk = inventory, Sopi = sales).
Same stack and conventions as Sopi: Vue 3 + TypeScript, Vite, Tailwind 4, shadcn-vue (reka-ui), TanStack Vue Query,
Pinia, vue-i18n, Supabase (Postgres + RLS + RPC).

## AI Agent Rules

- Data rules live in the database (RLS, triggers, `SECURITY DEFINER` RPCs). The UI only hides what the server refuses anyway.
- The client never decides a price, tax, total, balance or document number. It writes draft fields; the server computes the rest.
- Posted documents and journals are never updated or deleted; they are voided/reversed by an RPC that posts a mirror journal.
- Minimal diffs, no new dependency, no decorative UI. Mark deliberate shortcuts with a `ponytail:` comment naming the limit.
- Done means `pnpm build`, `pnpm lint`, `pnpm test:run` and `supabase/scratch/run.sh` (migrations + SQL smoke tests) pass.

## Layout

```
api/                 auth.ts (refresh-token BFF), keep-alive.js (Vercel Cron)
src/
  components/ui/     shadcn-vue primitives
  components/common/ shared building blocks (below)
  components/<area>/ feature components (journal/, invoice/, cash/, ...)
  composables/       data access (TanStack Vue Query)
  lib/               pure TypeScript, tested in lib/__tests__/
  locales/<lang>/    one JSON per area, merged at load (lib/i18n.ts)
  pages/             <Feature>Page.vue, lazy routes in router/index.ts
supabase/
  migrations/        schema, RLS, RPCs (numbered by area, see below)
  tests/             SQL smoke tests (one transaction, rolled back)
  scratch/           run.sh: throwaway Postgres with every migration + test; seed.sh: plus demo data
```

## Building Blocks

| Need | Use |
| --- | --- |
| Master list + form | `common/CrudTable` with a `fields` array; reads/writes through `useMasterRows`/`useSaveMasterRow` |
| Document list | `common/DocTable` (search, status filter, pager; you render the `<td>`s in the `row` slot) |
| Tabs in the URL | `common/TabBar` + `useTabParam` (`?tab=`) |
| Status chip | `common/DocStatus` (`status`, plus `paid`/`total`/`due` for receivables and payables → partial/overdue) |
| Reject / void prompt | `common/ReasonDialog` (emits the reason; the server requires one) |
| Simple confirm | `common/ConfirmDialog` |
| Export rows | `common/ExportMenu` (`rows` is a function, evaluated on click) |
| Short select | `common/AppSelect`; long lists (accounts, partners, items) `common/SearchSelect` (same props) |
| Money input (IDR whole rupiah) | `common/MoneyInput`; foreign amounts/rates: native `<input type="number" step="0.01">` with `FIELD_CLASS` |
| Date range | `common/PeriodFilter` |
| Charts | `charts/BarChart`, `charts/LineChart`, `charts/DonutChart` |
| Lookups | `useAccountOptions`, `usePartnerOptions`, `useBankOptions`, `useTaxOptions`, `useSimpleOptions`, `useCurrencyOptions`, `usePeriodOptions` (`composables/useLookups.ts`) |
| Read RPC (reports) | `useRpcQuery(name, () => args or null)` |
| Write RPC | `useRpcMutation(name, [table keys to refresh])` |
| Draft header + lines | `useCreateDocument(headerTable, linesTable, parentKey)`; edit lines of a draft with `useSaveMasterRow`/`useDeleteMasterRow` |
| Server error toast | `const serverError = useServerError(); toast.error(serverError(err))` |
| Permission check | `usePermissions().can(feature, action)` or `<Can feature action>` |
| Formatting | `formatMoney(v, currency)`, `formatAmount(v)` (statements: brackets for negatives), `formatDate`, `formatRate`, `isoDate`, `monthStart`, `monthEnd` (`lib/format.ts`) |

Conventions:
- A page opens a record from the URL: `?id=<id>` for documents and partners, `?account=<id>` on the ledger. The command palette links that way.
- Document numbers are null until posting; show `doc_no ?? "Draft #" + id`.
- Every mutation: `try { await m.mutateAsync(args); toast.success(t("common.saved")) } catch (e) { toast.error(serverError(e)) }`.
- Buttons follow permissions *and* status: e.g. "Ajukan" only on draft with create/update, "Setujui" only in `/approvals`.

## Design Language

- Frame: white `shell-panel` sidebar and toolbar on a cool paper canvas; the page title comes from route meta, pages do not render their own h1.
- Cards: `bg-card rounded-2xl border`, no shadow. Dashed dividers inside a card. Committing buttons get `active:scale-95`.
- Type: Plus Jakarta Sans; `font-mono` (JetBrains Mono) only for document numbers and account codes. Tables are tabular-nums; money right-aligned.
- Color roles: `primary` deep teal (actions), `primary-soft` tinted surfaces, `success` green for money in, rose for money out/destructive. No new accent colors per feature.
- One loud element: the dashboard cash position on `ledger-strip` (ruled ledger paper). Do not reuse it elsewhere.
- Labels in sentence case; money via `formatMoney`/`formatAmount` (`id-ID`).

## Database

Migrations, in order: `auth_access` (roles, features, permissions, profiles, audit) · `master_data` (currencies, FX rates, chart of accounts, account map,
cost centers, terms, taxes, partners, projects, items, bank accounts, fiscal years/periods, document counters) · `ledger` (journals, posting, reversal,
manual journal workflow, recurring journals) · `receivable_payable` (invoices/notes/bills, payments, allocations, note applications, FX realized) ·
`cash_bank` (cash in/out, transfers, expense claims, bank statements & reconciliation) · `assets_budget_close` (fixed assets & depreciation, budgets,
VAT settlement, FX revaluation, period checklist & closing, year-end closing, approval inbox) · `reports` · `system_demo`.

Rules:
- **Single posting path.** Every journal is posted by `gl_post_journal` (directly or via `gl_create`): it checks the period is open (`PERIOD_CLOSED`/`PERIOD_MISSING`),
  the journal balances (`JOURNAL_UNBALANCED`), every account is postable, and manual journals avoid control accounts (`CONTROL_ACCOUNT`).
  `gl_create` books a residue of at most 1.00 (FX rounding) to the `rounding` account.
- **Immutability.** `guard_journal`/`guard_journal_line` block any change to a posted journal, even for SECURITY DEFINER code; only posted → reversed (with `reversed_by`) is allowed.
  Reports count journals with status `posted` or `reversed` (the reversal is its own posted journal).
- **Maker-checker.** Manual journals (when `require_journal_approval`), bills and outgoing payments/cash at or above `approval_threshold`, sales invoices beyond the
  customer's credit limit, and every expense claim go to `submitted`; `decide_*` (or the generic `decide_document(kind, id, approve, reason)`) needs `approval:update`
  and refuses the creator (`SELF_APPROVAL`). `pending_approvals()` lists them.
- **Documents.** Clients insert/update only draft columns (column grants); line amounts, taxes and header totals are computed by triggers
  (`compute_invoice_line`, `invoice_recalc`, `compute_cash_line`). `guard_draft_doc` refuses API edits of non-drafts.
- **Receivables/payables.** One table `t_invoices` (`doc_type`: sales_invoice, sales_credit, purchase_bill, purchase_debit). Control accounts come from `m_account_map`
  (`receivable`, `payable`) and carry `partner_id` on every line, so `aging()` always equals the ledger (smoke-tested). Payments settle documents through
  `t_payment_allocations`; notes through `t_note_applications` (a note with `original_invoice_id` applies itself on posting). Different rates → `settle_fx` posts realized FX.
  Customer-withheld PPh (`wht_amount` on a receipt) goes to the tax's `sales_account_id` (prepaid tax). Supplier PPh is withheld on the bill line (`wht_tax_id`).
- **Tax.** PPN uses `dpp_factor` (11/12 per PMK 131/2024 → effective 11%). `settle_vat(period)` moves VAT balances into VAT payable/overpaid. Faktur numbers can be set after posting (`set_tax_invoice_no`).
- **Assets.** `run_depreciation(period)` posts one journal per period (straight line catches up skipped months; declining is double-declining monthly). `asset_schedule(id)` shows posted + projected months.
- **Closing.** `period_checklist(period)` lists open work (submitted docs block). `close_period` requires earlier periods closed; `reopen_period`/`close_fiscal_year`/`reopen_fiscal_year` need `period:delete` (Admin).
  `revalue_fx(date)` posts unrealized FX and its reversal on the next day.
- Business errors are `UPPER_SNAKE` messages; add new ones to `serverErrors` in both `locales/*/core.json`.
- Every migration that adds a function revokes `EXECUTE` from `PUBLIC, anon` and grants client RPCs to `authenticated` explicitly; `finance_smoke.sql` fails if anon can execute anything else.
- `superadmin_reset_data()` truncates everything and re-seeds defaults; a migration that adds a table adds it there.

Roles (rank): Admin 1 · Finance Manager 2 · Accountant 3 · Finance Staff 4 · Auditor 5 (read-only) · Employee 6 (own expense claims only).

## Tests & Local Database

```bash
pnpm test:run                     # Vitest, src/**/__tests__/*.test.ts
supabase/scratch/run.sh           # throwaway Postgres 17 (docker) + every migration + every SQL smoke test
supabase/scratch/run.sh types     # ... and regenerate src/integrations/supabase/types.ts
supabase/scratch/seed.sh          # fresh DB + demo data (10 months through the real RPCs)
psql -h 127.0.0.1 -p 55611 -U postgres   # password postgres; the container stays up
```

## Deployment Notes

- Create a Supabase project, put its ref in `supabase/config.toml` and `vercel.json` (`<project-ref>`), then `supabase db push` and `supabase functions deploy`.
- First Admin: `SELECT public.superadmin_bootstrap('you@example.com', 'StrongPass1');` in the SQL editor. Demo data: `SELECT public.seed_demo_data();` (demo users `*@findesk.demo`, password `Demo12345`).
- The CSP `sha256-` is the inline theme script in `index.html`; recompute it whenever that script changes.
