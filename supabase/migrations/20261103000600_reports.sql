-- Reports. All read the ledger through SECURITY DEFINER functions gated on reports:read (dashboard:read for the dashboard).
-- "Effective" journals are posted or reversed ones: a reversal is its own posted journal, so both count.

CREATE FUNCTION public.report_gate(p_feature text DEFAULT 'reports') RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission(p_feature, 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
END;
$$;

CREATE FUNCTION public.natural_sign(p_type text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT CASE WHEN p_type IN ('asset', 'expense') THEN 1 ELSE -1 END $$;

CREATE FUNCTION public.cash_flow_section(p_subtype text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE
    WHEN p_subtype IN ('cash', 'bank') THEN 'cash'
    WHEN p_subtype IN ('fixed_asset', 'other_asset') THEN 'investing'
    WHEN p_subtype IN ('long_term_liability', 'equity', 'retained_earnings') THEN 'financing'
    WHEN p_subtype IN ('revenue', 'other_income', 'cogs', 'expense', 'depreciation', 'other_expense', 'tax_expense') THEN 'income'
    ELSE 'operating' END;
$$;

CREATE FUNCTION public.trial_balance(p_from date, p_to date, p_cost_center_id bigint DEFAULT NULL, p_project_id bigint DEFAULT NULL,
                                     p_exclude_closing boolean DEFAULT false)
RETURNS TABLE (account_id bigint, code text, name text, account_type text, subtype text, parent_id bigint, is_postable boolean,
               opening numeric, debit numeric, credit numeric, closing numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate();
  RETURN QUERY
  WITH mv AS (
    SELECT l.account_id,
           sum(CASE WHEN j.journal_date < p_from THEN l.debit - l.credit ELSE 0 END) AS opening,
           sum(CASE WHEN j.journal_date >= p_from THEN l.debit ELSE 0 END) AS debit,
           sum(CASE WHEN j.journal_date >= p_from THEN l.credit ELSE 0 END) AS credit
      FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
     WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= p_to
       AND (p_cost_center_id IS NULL OR l.cost_center_id = p_cost_center_id)
       AND (p_project_id IS NULL OR l.project_id = p_project_id)
       AND NOT (p_exclude_closing AND j.kind = 'closing' AND j.journal_date >= p_from)
     GROUP BY l.account_id)
  SELECT a.id, a.code, a.name, a.account_type, a.subtype, a.parent_id, a.is_postable,
         COALESCE(mv.opening, 0), COALESCE(mv.debit, 0), COALESCE(mv.credit, 0),
         COALESCE(mv.opening, 0) + COALESCE(mv.debit, 0) - COALESCE(mv.credit, 0)
    FROM m_accounts a LEFT JOIN mv ON mv.account_id = a.id
   ORDER BY a.code;
END;
$$;

CREATE FUNCTION public.general_ledger(p_account_id bigint, p_from date, p_to date, p_cost_center_id bigint DEFAULT NULL)
RETURNS TABLE (line_id bigint, journal_id bigint, journal_date date, doc_no text, kind text, reference text, memo text, partner text,
               cost_center text, debit numeric, credit numeric, balance numeric, source_type text, source_id bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_opening numeric;
BEGIN
  IF NOT can_read_ledger() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT COALESCE(sum(l.debit - l.credit), 0) INTO v_opening FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
   WHERE l.account_id = p_account_id AND j.status IN ('posted', 'reversed') AND j.journal_date < p_from
     AND (p_cost_center_id IS NULL OR l.cost_center_id = p_cost_center_id);
  RETURN QUERY
  SELECT NULL::bigint, NULL::bigint, p_from, NULL::text, 'opening'::text, NULL::text, 'Saldo awal'::text, NULL::text, NULL::text,
         0::numeric, 0::numeric, v_opening, NULL::text, NULL::bigint
  UNION ALL
  SELECT l.id, j.id, j.journal_date, j.doc_no, j.kind, j.reference, COALESCE(l.memo, j.memo), pa.name, cc.code, l.debit, l.credit,
         v_opening + sum(l.debit - l.credit) OVER (ORDER BY j.journal_date, j.id, l.id), j.source_type, j.source_id
    FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
    LEFT JOIN m_partners pa ON pa.id = l.partner_id LEFT JOIN m_cost_centers cc ON cc.id = l.cost_center_id
   WHERE l.account_id = p_account_id AND j.status IN ('posted', 'reversed') AND j.journal_date BETWEEN p_from AND p_to
     AND (p_cost_center_id IS NULL OR l.cost_center_id = p_cost_center_id)
   ORDER BY 3, 2 NULLS FIRST, 1 NULLS FIRST;
END;
$$;

CREATE FUNCTION public.balance_sheet(p_as_of date)
RETURNS TABLE (account_id bigint, code text, name text, account_type text, subtype text, parent_id bigint, is_postable boolean, balance numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate();
  RETURN QUERY
  WITH bal AS (
    SELECT l.account_id, sum(l.debit - l.credit) AS net FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
     WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= p_as_of GROUP BY l.account_id)
  SELECT a.id, a.code, a.name, a.account_type, a.subtype, a.parent_id, a.is_postable, natural_sign(a.account_type) * COALESCE(b.net, 0)
    FROM m_accounts a LEFT JOIN bal b ON b.account_id = a.id
   WHERE a.account_type IN ('asset', 'liability', 'equity')
  UNION ALL
  SELECT NULL, 'CYE', 'Laba (rugi) belum ditutup', 'equity', 'retained_earnings', (SELECT x.id FROM m_accounts x WHERE x.code = '3'), true,
         -COALESCE(sum(b.net), 0)
    FROM bal b JOIN m_accounts a ON a.id = b.account_id WHERE a.account_type IN ('revenue', 'expense')
  ORDER BY 2;
END;
$$;

CREATE FUNCTION public.income_statement(p_from date, p_to date, p_cost_center_id bigint DEFAULT NULL, p_project_id bigint DEFAULT NULL)
RETURNS TABLE (account_id bigint, code text, name text, account_type text, subtype text, parent_id bigint, is_postable boolean, amount numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate();
  RETURN QUERY
  WITH mv AS (
    SELECT l.account_id, sum(l.debit - l.credit) AS net FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
     WHERE j.status IN ('posted', 'reversed') AND j.kind <> 'closing' AND j.journal_date BETWEEN p_from AND p_to
       AND (p_cost_center_id IS NULL OR l.cost_center_id = p_cost_center_id)
       AND (p_project_id IS NULL OR l.project_id = p_project_id)
     GROUP BY l.account_id)
  SELECT a.id, a.code, a.name, a.account_type, a.subtype, a.parent_id, a.is_postable, natural_sign(a.account_type) * COALESCE(mv.net, 0)
    FROM m_accounts a LEFT JOIN mv ON mv.account_id = a.id
   WHERE a.account_type IN ('revenue', 'expense')
   ORDER BY a.code;
END;
$$;

CREATE FUNCTION public.cash_flow(p_from date, p_to date)
RETURNS TABLE (section text, account_id bigint, code text, name text, amount numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate();
  RETURN QUERY
  WITH mv AS (
    SELECT a.id, a.code, a.name, a.subtype,
           sum(CASE WHEN j.journal_date >= p_from AND j.kind <> 'closing' THEN l.debit - l.credit ELSE 0 END) AS net,
           sum(CASE WHEN j.journal_date < p_from THEN l.debit - l.credit ELSE 0 END) AS prior
      FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id JOIN m_accounts a ON a.id = l.account_id
     WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= p_to
     GROUP BY a.id)
  SELECT 'operating'::text, NULL::bigint, 'NI'::text, 'Laba (rugi) bersih'::text, -COALESCE(sum(net), 0)
    FROM mv WHERE cash_flow_section(subtype) = 'income'
  UNION ALL
  SELECT cash_flow_section(subtype), id, mv.code, mv.name, -net FROM mv
   WHERE cash_flow_section(subtype) IN ('operating', 'investing', 'financing') AND net <> 0
  UNION ALL
  SELECT 'cash_opening', NULL, 'CASH0', 'Kas & bank awal periode', COALESCE(sum(prior), 0) FROM mv WHERE subtype IN ('cash', 'bank')
  UNION ALL
  SELECT 'cash_closing', NULL, 'CASH1', 'Kas & bank akhir periode', COALESCE(sum(prior + net), 0) FROM mv WHERE subtype IN ('cash', 'bank');
END;
$$;

CREATE FUNCTION public.aging(p_side text, p_as_of date)
RETURNS TABLE (partner_id bigint, partner text, doc_id bigint, doc_no text, doc_type text, invoice_date date, due_date date,
               currency text, open_amount numeric, open_base numeric, days_overdue integer, bucket text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT (has_permission(p_side, 'read') OR has_permission('reports', 'read')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN QUERY
  WITH docs AS (
    SELECT i.partner_id, i.id, i.doc_no, i.doc_type, i.invoice_date, i.due_date, i.currency, i.fx_rate,
           (CASE WHEN i.doc_type IN ('sales_invoice', 'purchase_bill') THEN 1 ELSE -1 END)
           * (i.total
              - COALESCE((SELECT sum(a.amount) FROM t_payment_allocations a WHERE a.invoice_id = i.id AND a.applied_date <= p_as_of), 0)
              - COALESCE((SELECT sum(n.amount) FROM t_note_applications n WHERE (n.invoice_id = i.id OR n.note_id = i.id) AND n.applied_date <= p_as_of), 0)
             ) AS open
      FROM t_invoices i
     WHERE doc_feature(i.doc_type) = p_side AND i.status IN ('posted', 'paid') AND i.invoice_date <= p_as_of
    UNION ALL
    SELECT p.partner_id, p.id, p.doc_no, 'payment', p.payment_date, p.payment_date, p.currency, p.fx_rate,
           -(p.amount + p.wht_amount
             - COALESCE((SELECT sum(a.amount) FROM t_payment_allocations a WHERE a.payment_id = p.id AND a.applied_date <= p_as_of), 0))
      FROM t_payments p
     WHERE doc_feature(p.direction) = p_side AND p.status = 'posted' AND p.payment_date <= p_as_of)
  SELECT d.partner_id, pa.name, d.id, d.doc_no, d.doc_type, d.invoice_date, d.due_date, d.currency, d.open, round(d.open * d.fx_rate, 2),
         greatest(p_as_of - d.due_date, 0),
         CASE WHEN d.open < 0 OR p_as_of <= d.due_date THEN 'current'
              WHEN p_as_of - d.due_date <= 30 THEN 'd1_30' WHEN p_as_of - d.due_date <= 60 THEN 'd31_60'
              WHEN p_as_of - d.due_date <= 90 THEN 'd61_90' ELSE 'd90_plus' END
    FROM docs d JOIN m_partners pa ON pa.id = d.partner_id
   WHERE d.open <> 0
   ORDER BY pa.name, d.due_date;
END;
$$;

CREATE FUNCTION public.partner_statement(p_partner_id bigint, p_side text, p_from date, p_to date)
RETURNS TABLE (journal_date date, doc_no text, kind text, reference text, memo text, debit numeric, credit numeric, balance numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_acc bigint;
  v_sign integer := natural_sign(CASE p_side WHEN 'receivable' THEN 'asset' ELSE 'liability' END);
BEGIN
  IF NOT (has_permission(p_side, 'read') OR has_permission('reports', 'read') OR has_permission('partner', 'read')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  v_acc := account_map(p_side);
  RETURN QUERY
  WITH t AS (
    SELECT j.journal_date AS d, j.doc_no AS dno, j.kind AS k, j.reference AS ref, COALESCE(l.memo, j.memo) AS m,
           l.debit AS dr, l.credit AS cr, j.id AS jid, l.id AS lid
      FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
     WHERE l.account_id = v_acc AND l.partner_id = p_partner_id AND j.status IN ('posted', 'reversed') AND j.journal_date <= p_to
       AND j.kind <> 'fx_reval' AND NOT (j.kind = 'reversal' AND (SELECT o.kind FROM t_journals o WHERE o.id = j.reversal_of) = 'fx_reval')),
  o AS (SELECT COALESCE(sum(t.dr - t.cr), 0) AS v FROM t WHERE t.d < p_from)
  SELECT x.d, x.dno, x.k, x.ref, x.m, x.dr, x.cr, x.bal FROM (
    SELECT p_from AS d, NULL::text AS dno, 'opening'::text AS k, NULL::text AS ref, 'Saldo awal'::text AS m,
           0::numeric AS dr, 0::numeric AS cr, v_sign * o.v AS bal, 0 AS ord, 0::bigint AS jid, 0::bigint AS lid FROM o
    UNION ALL
    SELECT t.d, t.dno, t.k, t.ref, t.m, t.dr, t.cr, v_sign * (o.v + sum(t.dr - t.cr) OVER (ORDER BY t.d, t.jid, t.lid)), 1, t.jid, t.lid
      FROM t, o WHERE t.d >= p_from) x
   ORDER BY x.d, x.ord, x.jid, x.lid;
END;
$$;

CREATE FUNCTION public.budget_vs_actual(p_budget_id bigint, p_from_period integer DEFAULT 1, p_to_period integer DEFAULT 12)
RETURNS TABLE (account_id bigint, code text, name text, account_type text, budget numeric, actual numeric, variance numeric, used_pct numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  b t_budgets;
  v_from date;
  v_to date;
BEGIN
  IF NOT (has_permission('budget', 'read') OR has_permission('reports', 'read')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO b FROM t_budgets WHERE id = p_budget_id;
  SELECT min(start_date), max(end_date) INTO v_from, v_to FROM m_periods
   WHERE fiscal_year_id = b.fiscal_year_id AND period_no BETWEEN p_from_period AND p_to_period;
  RETURN QUERY
  WITH bud AS (
    SELECT bl.account_id, sum(bl.amount) AS amt FROM t_budget_lines bl
     WHERE bl.budget_id = p_budget_id AND bl.period_no BETWEEN p_from_period AND p_to_period GROUP BY bl.account_id),
  act AS (
    SELECT l.account_id, sum(l.debit - l.credit) AS net FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
     WHERE j.status IN ('posted', 'reversed') AND j.kind <> 'closing' AND j.journal_date BETWEEN v_from AND v_to
       AND (b.cost_center_id IS NULL OR l.cost_center_id = b.cost_center_id)
       AND l.account_id IN (SELECT bud.account_id FROM bud)
     GROUP BY l.account_id)
  SELECT a.id, a.code, a.name, a.account_type, bud.amt, natural_sign(a.account_type) * COALESCE(act.net, 0),
         bud.amt - natural_sign(a.account_type) * COALESCE(act.net, 0),
         CASE WHEN bud.amt = 0 THEN NULL ELSE round(100 * natural_sign(a.account_type) * COALESCE(act.net, 0) / bud.amt, 1) END
    FROM bud JOIN m_accounts a ON a.id = bud.account_id LEFT JOIN act ON act.account_id = bud.account_id
   ORDER BY a.code;
END;
$$;

CREATE FUNCTION public.vat_report(p_period_id bigint)
RETURNS TABLE (side text, doc_kind text, doc_id bigint, doc_no text, doc_date date, partner text, npwp text, tax_invoice_no text,
               tax_invoice_date date, tax_code text, tax_base numeric, vat numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
BEGIN
  PERFORM report_gate('tax');
  SELECT * INTO p FROM m_periods WHERE id = p_period_id;
  RETURN QUERY
  SELECT CASE WHEN i.doc_type LIKE 'sales%' THEN 'output' ELSE 'input' END, i.doc_type, i.id, i.doc_no, i.invoice_date, pa.name, pa.npwp,
         i.tax_invoice_no, i.tax_invoice_date, t.code,
         doc_sign_natural.s * round(sum(l.tax_base) * i.fx_rate, 2), doc_sign_natural.s * round(sum(l.tax_amount) * i.fx_rate, 2)
    FROM t_invoices i JOIN t_invoice_lines l ON l.invoice_id = i.id JOIN m_taxes t ON t.id = l.tax_id
    JOIN m_partners pa ON pa.id = i.partner_id
    CROSS JOIN LATERAL (SELECT CASE WHEN i.doc_type IN ('sales_invoice', 'purchase_bill') THEN 1 ELSE -1 END AS s) doc_sign_natural
   WHERE i.status IN ('posted', 'paid') AND i.invoice_date BETWEEN p.start_date AND p.end_date
   GROUP BY i.id, pa.id, t.id, doc_sign_natural.s
  UNION ALL
  SELECT CASE c.direction WHEN 'in' THEN 'output' ELSE 'input' END, 'cash_' || c.direction, c.id, c.doc_no, c.txn_date,
         COALESCE(pa.name, c.payee), pa.npwp, c.reference, NULL::date, t.code,
         round(sum(l.tax_base) * c.fx_rate, 2), round(sum(l.tax_amount) * c.fx_rate, 2)
    FROM t_cash_txns c JOIN t_cash_txn_lines l ON l.txn_id = c.id JOIN m_taxes t ON t.id = l.tax_id
    LEFT JOIN m_partners pa ON pa.id = c.partner_id
   WHERE c.status = 'posted' AND c.txn_date BETWEEN p.start_date AND p.end_date
   GROUP BY c.id, pa.id, t.id
   ORDER BY 1 DESC, 5, 4;
END;
$$;

CREATE FUNCTION public.wht_report(p_from date, p_to date)
RETURNS TABLE (side text, wht_type text, tax_code text, doc_id bigint, doc_no text, doc_date date, partner text, npwp text,
               slip_no text, gross numeric, wht numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate('tax');
  RETURN QUERY
  SELECT 'withheld_by_us', t.wht_type, t.code, i.id, i.doc_no, i.invoice_date, pa.name, pa.npwp, i.reference,
         CASE WHEN i.doc_type = 'purchase_bill' THEN 1 ELSE -1 END * round(sum(l.line_subtotal) * i.fx_rate, 2),
         CASE WHEN i.doc_type = 'purchase_bill' THEN 1 ELSE -1 END * round(sum(l.wht_amount) * i.fx_rate, 2)
    FROM t_invoices i JOIN t_invoice_lines l ON l.invoice_id = i.id JOIN m_taxes t ON t.id = l.wht_tax_id
    JOIN m_partners pa ON pa.id = i.partner_id
   WHERE i.status IN ('posted', 'paid') AND i.invoice_date BETWEEN p_from AND p_to
   GROUP BY i.id, pa.id, t.id
  UNION ALL
  SELECT 'withheld_from_us', t.wht_type, t.code, p.id, p.doc_no, p.payment_date, pa.name, pa.npwp, p.wht_slip_no,
         round(p.wht_amount * 100 / NULLIF(t.rate, 0) * p.fx_rate, 2), round(p.wht_amount * p.fx_rate, 2)
    FROM t_payments p JOIN m_taxes t ON t.id = p.wht_tax_id JOIN m_partners pa ON pa.id = p.partner_id
   WHERE p.status = 'posted' AND p.payment_date BETWEEN p_from AND p_to
   ORDER BY 1, 6;
END;
$$;

CREATE FUNCTION public.dashboard_summary(p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM report_gate('dashboard');
  WITH eff AS (
    SELECT l.*, j.journal_date, j.kind, a.account_type, a.subtype FROM t_journal_lines l
      JOIN t_journals j ON j.id = l.journal_id JOIN m_accounts a ON a.id = l.account_id
     WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= p_to),
  bal AS (SELECT subtype, account_type, sum(debit - credit) AS net FROM eff GROUP BY subtype, account_type),
  pl AS (SELECT subtype, -sum(debit - credit) AS amt FROM eff WHERE journal_date >= p_from AND kind <> 'closing'
          AND account_type IN ('revenue', 'expense') GROUP BY subtype),
  months AS (
    SELECT to_char(date_trunc('month', journal_date), 'YYYY-MM') AS m,
           sum(CASE WHEN account_type = 'revenue' THEN credit - debit ELSE 0 END) AS revenue,
           sum(CASE WHEN account_type = 'expense' THEN debit - credit ELSE 0 END) AS expense
      FROM eff WHERE kind <> 'closing' AND journal_date > (date_trunc('month', p_to) - interval '12 months')
       AND account_type IN ('revenue', 'expense') GROUP BY 1),
  cash_months AS (
    SELECT to_char(date_trunc('month', journal_date), 'YYYY-MM') AS m,
           sum(debit) FILTER (WHERE kind NOT IN ('transfer', 'fx_reval', 'reversal')) AS cash_in,
           sum(credit) FILTER (WHERE kind NOT IN ('transfer', 'fx_reval', 'reversal')) AS cash_out
      FROM eff WHERE subtype IN ('cash', 'bank') AND journal_date > (date_trunc('month', p_to) - interval '12 months') GROUP BY 1),
  open_docs AS (
    SELECT doc_feature(doc_type) AS side, due_date, round(doc_sign(doc_type) * (CASE WHEN doc_type LIKE 'sales%' THEN 1 ELSE -1 END)
             * (total - paid_amount) * fx_rate, 2) AS amt
      FROM t_invoices WHERE status = 'posted'),
  rev AS (SELECT COALESCE(sum(amt) FILTER (WHERE subtype IN ('revenue')), 0) AS sales,
                 COALESCE(sum(amt) FILTER (WHERE subtype = 'cogs'), 0) AS cogs,
                 COALESCE(sum(amt), 0) AS net FROM pl)
  SELECT jsonb_build_object(
    'cash', (SELECT COALESCE(sum(net), 0) FROM bal WHERE subtype IN ('cash', 'bank')),
    'receivable', (SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'receivable'),
    'receivable_overdue', (SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'receivable' AND amt > 0 AND due_date < p_to),
    'payable', (SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'payable'),
    'payable_overdue', (SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'payable' AND amt > 0 AND due_date < p_to),
    'revenue', (SELECT COALESCE(sum(amt), 0) FROM pl WHERE subtype IN ('revenue', 'other_income')),
    'expense', (SELECT -COALESCE(sum(amt), 0) FROM pl WHERE subtype NOT IN ('revenue', 'other_income')),
    'net_income', (SELECT net FROM rev),
    'gross_margin_pct', (SELECT CASE WHEN sales = 0 THEN NULL ELSE round(100 * (sales + cogs) / sales, 1) END FROM rev),
    'current_ratio', (SELECT CASE WHEN cl = 0 THEN NULL ELSE round(ca / cl, 2) END FROM (
        SELECT sum(net) FILTER (WHERE subtype IN ('cash', 'bank', 'receivable', 'inventory', 'prepaid', 'tax_prepaid', 'other_current_asset')) AS ca,
               -sum(net) FILTER (WHERE subtype IN ('payable', 'tax_payable', 'accrued', 'other_current_liability')) AS cl FROM bal) x),
    'dso', (SELECT CASE WHEN r.sales <= 0 THEN NULL ELSE round((SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'receivable')
             / r.sales * (p_to - p_from + 1)) END FROM rev r),
    'dpo', (SELECT CASE WHEN x.spend <= 0 THEN NULL
             ELSE round((SELECT COALESCE(sum(amt), 0) FROM open_docs WHERE side = 'payable') / x.spend * (p_to - p_from + 1)) END
              FROM (SELECT -COALESCE(sum(amt), 0) AS spend FROM pl WHERE subtype IN ('cogs', 'expense')) x),
    'banks', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', b.id, 'code', b.code, 'name', b.name, 'kind', b.kind, 'currency', b.currency,
                 'base', COALESCE(x.base, 0), 'fc', COALESCE(x.fc, 0)) ORDER BY b.code), '[]')
                FROM m_bank_accounts b LEFT JOIN (SELECT account_id, sum(debit - credit) base, sum(COALESCE(fc_amount, debit - credit)) fc
                                                   FROM eff GROUP BY account_id) x ON x.account_id = b.gl_account_id
               WHERE b.is_active),
    'monthly', (SELECT COALESCE(jsonb_agg(jsonb_build_object('month', m, 'revenue', revenue, 'expense', expense,
                   'net', revenue - expense) ORDER BY m), '[]') FROM months),
    'cash_monthly', (SELECT COALESCE(jsonb_agg(jsonb_build_object('month', m, 'in', COALESCE(cash_in, 0), 'out', COALESCE(cash_out, 0)) ORDER BY m), '[]')
                       FROM cash_months),
    'expense_breakdown', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'amount', amt) ORDER BY amt DESC), '[]') FROM (
        SELECT a.name, sum(e.debit - e.credit) amt FROM eff e JOIN m_accounts a ON a.id = e.account_id
         WHERE e.journal_date >= p_from AND e.kind <> 'closing' AND e.account_type = 'expense' GROUP BY a.name
        HAVING sum(e.debit - e.credit) > 0 ORDER BY 2 DESC LIMIT 6) x),
    'top_customers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'amount', amt) ORDER BY amt DESC), '[]') FROM (
        SELECT pa.name, sum(doc_sign(i.doc_type) * round(i.subtotal * i.fx_rate, 2)) amt FROM t_invoices i JOIN m_partners pa ON pa.id = i.partner_id
         WHERE i.doc_type LIKE 'sales%' AND i.status IN ('posted', 'paid') AND i.invoice_date BETWEEN p_from AND p_to
         GROUP BY pa.name ORDER BY 2 DESC LIMIT 5) x),
    'forecast', (SELECT jsonb_agg(jsonb_build_object('bucket', b.k,
                   'in', COALESCE((SELECT sum(amt) FROM open_docs WHERE side = 'receivable' AND amt > 0
                                    AND greatest(due_date, p_to) BETWEEN p_to + b.lo AND p_to + b.hi), 0),
                   'out', COALESCE((SELECT sum(amt) FROM open_docs WHERE side = 'payable' AND amt > 0
                                    AND greatest(due_date, p_to) BETWEEN p_to + b.lo AND p_to + b.hi), 0)) ORDER BY b.lo)
                   FROM (VALUES ('d0_7', 0, 7), ('d8_30', 8, 30), ('d31_60', 31, 60), ('d61_90', 61, 90)) b(k, lo, hi)),
    'pending_approvals', CASE WHEN has_permission('approval', 'read') THEN (SELECT count(*) FROM pending_approvals()) ELSE 0 END
  ) INTO v;
  RETURN v;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.report_gate(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.natural_sign(text), public.cash_flow_section(text),
  public.trial_balance(date, date, bigint, bigint, boolean), public.general_ledger(bigint, date, date, bigint),
  public.balance_sheet(date), public.income_statement(date, date, bigint, bigint), public.cash_flow(date, date),
  public.aging(text, date), public.partner_statement(bigint, text, date, date), public.budget_vs_actual(bigint, integer, integer),
  public.vat_report(bigint), public.wht_report(date, date), public.dashboard_summary(date, date)
TO authenticated;
REVOKE EXECUTE ON FUNCTION public.natural_sign(text), public.cash_flow_section(text),
  public.trial_balance(date, date, bigint, bigint, boolean), public.general_ledger(bigint, date, date, bigint),
  public.balance_sheet(date), public.income_statement(date, date, bigint, bigint), public.cash_flow(date, date),
  public.aging(text, date), public.partner_statement(bigint, text, date, date), public.budget_vs_actual(bigint, integer, integer),
  public.vat_report(bigint), public.wht_report(date, date), public.dashboard_summary(date, date)
FROM PUBLIC, anon;
