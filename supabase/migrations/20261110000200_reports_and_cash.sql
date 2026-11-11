
ALTER TABLE public.t_cash_txns ADD COLUMN tax_invoice_no text, ADD COLUMN tax_invoice_date date;
GRANT INSERT (tax_invoice_no, tax_invoice_date), UPDATE (tax_invoice_no, tax_invoice_date) ON public.t_cash_txns TO authenticated;

CREATE OR REPLACE FUNCTION public.save_cash_txn_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, partner_id, payee, fx_rate, reference, description, tax_invoice_no, tax_invoice_date)
    SELECT h.direction, h.bank_account_id, h.txn_date, h.partner_id, h.payee, h.fx_rate, h.reference, h.description, h.tax_invoice_no, h.tax_invoice_date
      FROM jsonb_populate_record(NULL::t_cash_txns, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_cash_txns', v_id);
    UPDATE t_cash_txns t SET bank_account_id = h.bank_account_id, txn_date = h.txn_date, partner_id = h.partner_id, payee = h.payee,
           fx_rate = h.fx_rate, reference = h.reference, description = h.description, tax_invoice_no = h.tax_invoice_no,
           tax_invoice_date = h.tax_invoice_date
      FROM jsonb_populate_record(NULL::t_cash_txns, p_header) h WHERE t.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501'; END IF;
    DELETE FROM t_cash_txn_lines WHERE txn_id = v_id;
  END IF;
  INSERT INTO t_cash_txn_lines (txn_id, account_id, description, amount, tax_id, cost_center_id, project_id)
  SELECT v_id, l.account_id, l.description, l.amount, l.tax_id, l.cost_center_id, l.project_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]')) e(v), LATERAL jsonb_populate_record(NULL::t_cash_txn_lines, e.v) l;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.vat_report(p_period_id bigint)
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
         COALESCE(pa.name, c.payee), pa.npwp, c.tax_invoice_no, c.tax_invoice_date, t.code,
         round(sum(l.tax_base) * c.fx_rate, 2), round(sum(l.tax_amount) * c.fx_rate, 2)
    FROM t_cash_txns c JOIN t_cash_txn_lines l ON l.txn_id = c.id JOIN m_taxes t ON t.id = l.tax_id
    LEFT JOIN m_partners pa ON pa.id = c.partner_id
   WHERE c.status = 'posted' AND c.txn_date BETWEEN p.start_date AND p.end_date
   GROUP BY c.id, pa.id, t.id
   ORDER BY 1 DESC, 5, 4;
END;
$$;

ALTER TABLE public.t_payments ADD COLUMN wht_base numeric(18,2),
  ADD CONSTRAINT t_payments_wht_base_check CHECK (wht_base IS NULL OR (wht_base >= 0 AND wht_amount <= wht_base));
GRANT INSERT (wht_base), UPDATE (wht_base) ON public.t_payments TO authenticated;

CREATE OR REPLACE FUNCTION public.save_payment_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount, wht_tax_id, wht_amount,
                            wht_base, wht_slip_no, reference, note)
    SELECT h.direction, h.partner_id, h.payment_date, h.bank_account_id, h.currency, h.fx_rate, h.amount, h.wht_tax_id,
           COALESCE(h.wht_amount, 0), h.wht_base, h.wht_slip_no, h.reference, h.note
      FROM jsonb_populate_record(NULL::t_payments, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_payments', v_id);
    UPDATE t_payments t SET partner_id = h.partner_id, payment_date = h.payment_date, bank_account_id = h.bank_account_id,
           currency = h.currency, fx_rate = h.fx_rate, amount = h.amount, wht_tax_id = h.wht_tax_id,
           wht_amount = COALESCE(h.wht_amount, 0), wht_base = h.wht_base, wht_slip_no = h.wht_slip_no, reference = h.reference, note = h.note
      FROM jsonb_populate_record(NULL::t_payments, p_header) h WHERE t.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501'; END IF;
    DELETE FROM t_payment_allocations WHERE payment_id = v_id;
  END IF;
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount)
  SELECT v_id, l.invoice_id, l.amount
    FROM jsonb_array_elements(COALESCE(p_lines, '[]')) e(v), LATERAL jsonb_populate_record(NULL::t_payment_allocations, e.v) l;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.wht_report(p_from date, p_to date)
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
         round(COALESCE(p.wht_base, p.wht_amount * 100 / NULLIF(t.rate, 0)) * p.fx_rate, 2), round(p.wht_amount * p.fx_rate, 2)
    FROM t_payments p JOIN m_taxes t ON t.id = p.wht_tax_id JOIN m_partners pa ON pa.id = p.partner_id
   WHERE p.status = 'posted' AND p.payment_date BETWEEN p_from AND p_to
   ORDER BY 1, 6;
END;
$$;

DROP FUNCTION public.general_ledger(bigint, date, date, bigint);
CREATE FUNCTION public.general_ledger(p_account_id bigint, p_from date, p_to date, p_cost_center_id bigint DEFAULT NULL)
RETURNS TABLE (line_id bigint, journal_id bigint, journal_date date, doc_no text, kind text, reference text, memo text, partner text,
               cost_center text, debit numeric, credit numeric, balance numeric, source_type text, source_id bigint, currency text, fc_amount numeric)
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
         0::numeric, 0::numeric, v_opening, NULL::text, NULL::bigint, NULL::text, NULL::numeric
  UNION ALL
  SELECT l.id, j.id, j.journal_date, j.doc_no, j.kind, j.reference, COALESCE(l.memo, j.memo), pa.name, cc.code, l.debit, l.credit,
         v_opening + sum(l.debit - l.credit) OVER (ORDER BY j.journal_date, j.id, l.id), j.source_type, j.source_id, l.currency, l.fc_amount
    FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
    LEFT JOIN m_partners pa ON pa.id = l.partner_id LEFT JOIN m_cost_centers cc ON cc.id = l.cost_center_id
   WHERE l.account_id = p_account_id AND j.status IN ('posted', 'reversed') AND j.journal_date BETWEEN p_from AND p_to
     AND (p_cost_center_id IS NULL OR l.cost_center_id = p_cost_center_id)
   ORDER BY 3, 2 NULLS FIRST, 1 NULLS FIRST;
END;
$$;

CREATE OR REPLACE FUNCTION public.period_checklist(p_period_id bigint)
RETURNS TABLE (item text, count bigint, blocking boolean, link text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
BEGIN
  IF NOT has_permission('period', 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO p FROM m_periods WHERE id = p_period_id;
  RETURN QUERY
  SELECT 'submitted_docs', (
      (SELECT count(*) FROM t_journals WHERE status = 'submitted' AND journal_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_invoices WHERE status = 'submitted' AND invoice_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_payments WHERE status = 'submitted' AND payment_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_cash_txns WHERE status = 'submitted' AND txn_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_expense_claims WHERE status = 'submitted' AND claim_date <= p.end_date)), true, '/approvals'
  UNION ALL
  SELECT 'draft_journals', (SELECT count(*) FROM t_journals WHERE status = 'draft' AND journal_date BETWEEN p.start_date AND p.end_date),
         false, '/journals'
  UNION ALL
  SELECT 'draft_invoices', (SELECT count(*) FROM t_invoices WHERE status = 'draft' AND invoice_date BETWEEN p.start_date AND p.end_date), false,
         CASE WHEN EXISTS (SELECT 1 FROM t_invoices WHERE status = 'draft' AND doc_type LIKE 'sales%'
                            AND invoice_date BETWEEN p.start_date AND p.end_date) THEN '/sales/invoices' ELSE '/purchases/bills' END
  UNION ALL
  SELECT 'draft_payments', (SELECT count(*) FROM t_payments WHERE status = 'draft' AND payment_date BETWEEN p.start_date AND p.end_date), false,
         CASE WHEN EXISTS (SELECT 1 FROM t_payments WHERE status = 'draft' AND direction = 'in'
                            AND payment_date BETWEEN p.start_date AND p.end_date) THEN '/sales/receipts' ELSE '/purchases/payments' END
  UNION ALL
  SELECT 'draft_cash', (SELECT count(*) FROM t_cash_txns WHERE status = 'draft' AND txn_date BETWEEN p.start_date AND p.end_date),
         false, '/cash?tab=txns'
  UNION ALL
  SELECT 'draft_transfers', (SELECT count(*) FROM t_bank_transfers WHERE status = 'draft' AND transfer_date BETWEEN p.start_date AND p.end_date),
         false, '/cash?tab=transfers'
  UNION ALL
  SELECT 'recurring_due', (SELECT count(*) FROM t_recurring_journals
                            WHERE is_active AND next_run <= p.end_date AND (end_date IS NULL OR next_run <= end_date)), false, '/journals?tab=recurring'
  UNION ALL
  SELECT 'depreciation', (SELECT count(*) FROM t_assets a WHERE a.status = 'active' AND a.method <> 'none' AND a.in_service_date <= p.end_date
                            AND asset_dep_amount(a, asset_month_index(a, p.end_date), asset_accumulated(a.id)) > 0
                            AND NOT EXISTS (SELECT 1 FROM t_asset_depreciation d WHERE d.asset_id = a.id AND d.period_id = p.id)), false, '/assets'
  UNION ALL
  SELECT 'unreconciled', (SELECT count(*) FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
                            JOIN m_bank_accounts b ON b.gl_account_id = l.account_id AND b.kind = 'bank'
                           WHERE j.status IN ('posted', 'reversed') AND j.journal_date BETWEEN p.start_date AND p.end_date
                             AND NOT EXISTS (SELECT 1 FROM t_bank_statement_lines s WHERE s.journal_line_id = l.id)), false, '/reconcile'
  UNION ALL
  SELECT 'vat_unsettled', CASE WHEN (SELECT is_pkp FROM m_settings WHERE id = 1)
                                AND NOT EXISTS (SELECT 1 FROM t_vat_settlements WHERE period_id = p.id AND status = 'posted')
                                AND EXISTS (SELECT 1 FROM t_invoices WHERE tax_total > 0 AND status IN ('posted', 'paid')
                                             AND invoice_date BETWEEN p.start_date AND p.end_date) THEN 1 ELSE 0 END::bigint, false, '/tax'
  UNION ALL
  SELECT 'claims_unpaid', (SELECT count(*) FROM t_expense_claims WHERE status = 'approved'), false, '/expenses'
  UNION ALL
  SELECT 'fx_unrevalued', CASE WHEN EXISTS (SELECT 1 FROM t_invoices WHERE status = 'posted' AND currency <> base_currency()
                                              AND invoice_date <= p.end_date)
                                AND NOT EXISTS (SELECT 1 FROM t_journals WHERE kind = 'fx_reval' AND journal_date = p.end_date AND reversal_of IS NULL)
                               THEN 1 ELSE 0 END::bigint, false, '/periods';
END;
$$;

CREATE FUNCTION public.bank_balances(p_as_of date DEFAULT NULL)
RETURNS TABLE (id bigint, code text, name text, kind text, currency text, is_active boolean, base numeric, fc numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('cash-bank', 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN QUERY
  SELECT b.id, b.code, b.name, b.kind, b.currency, b.is_active, COALESCE(x.base, 0), COALESCE(x.fc, 0)
    FROM m_bank_accounts b
    LEFT JOIN (SELECT l.account_id, sum(l.debit - l.credit) AS base, sum(COALESCE(l.fc_amount, l.debit - l.credit)) AS fc
                 FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
                WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= COALESCE(p_as_of, company_today())
                GROUP BY l.account_id) x ON x.account_id = b.gl_account_id
   ORDER BY b.code;
END;
$$;

CREATE FUNCTION public.asset_register_summary()
RETURNS TABLE (asset_id bigint, accumulated numeric, book_value numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('asset', 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN QUERY
  SELECT a.id, a.accumulated_opening + COALESCE(d.amt, 0), a.cost - a.accumulated_opening - COALESCE(d.amt, 0)
    FROM t_assets a LEFT JOIN (SELECT dep.asset_id AS aid, sum(dep.amount) AS amt FROM t_asset_depreciation dep GROUP BY dep.asset_id) d ON d.aid = a.id;
END;
$$;

CREATE FUNCTION public.cash_month_end(p_to date, p_months integer DEFAULT 12) RETURNS TABLE (month text, balance numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM report_gate('dashboard');
  RETURN QUERY
  SELECT to_char(m, 'YYYY-MM'), COALESCE((
      SELECT sum(l.debit - l.credit) FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
        JOIN m_accounts a ON a.id = l.account_id AND a.subtype IN ('cash', 'bank')
       WHERE j.status IN ('posted', 'reversed') AND j.journal_date <= least((m + interval '1 month - 1 day')::date, p_to)), 0)
    FROM generate_series(date_trunc('month', p_to) - (greatest(p_months, 1) - 1) * interval '1 month', date_trunc('month', p_to), interval '1 month') m
   ORDER BY 1;
END;
$$;

CREATE FUNCTION public.partner_payable_exposure(p_partner_id bigint) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('payable', 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN (SELECT COALESCE(sum(-doc_sign(doc_type) * round((total - paid_amount) * fx_rate, 2)), 0)
            FROM t_invoices WHERE partner_id = p_partner_id AND doc_type LIKE 'purchase%' AND status = 'posted');
END;
$$;

CREATE OR REPLACE FUNCTION public.revalue_fx(p_date date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_base text := base_currency();
  v_lines jsonb;
  v_net numeric;
  v_jid bigint;
  v_rev bigint;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT has_permission('period', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM t_journals WHERE kind = 'fx_reval' AND journal_date = p_date AND status IN ('posted', 'reversed')
              AND reversal_of IS NULL) THEN
    RAISE EXCEPTION 'FX_REVAL_EXISTS' USING errcode = 'P0001';
  END IF;
  PERFORM ensure_fiscal_year(extract(year FROM p_date + 1)::int);

  WITH rates AS (
    SELECT c.code, fx_rate_on(c.code, p_date) AS rate FROM m_currencies c WHERE c.code <> v_base),
  deltas AS (
    SELECT doc_control_account(i.doc_type) AS account_id, i.partner_id,
           doc_sign(i.doc_type) * (round(u.open * r.rate, 2) - round(u.open * i.fx_rate, 2)) AS delta
      FROM t_invoices i JOIN rates r ON r.code = i.currency
      CROSS JOIN LATERAL (SELECT i.total
          - COALESCE((SELECT sum(a.amount) FROM t_payment_allocations a WHERE a.invoice_id = i.id AND a.applied_date <= p_date), 0)
          - COALESCE((SELECT sum(n.amount) FROM t_note_applications n WHERE i.id IN (n.invoice_id, n.note_id) AND n.applied_date <= p_date), 0) AS open) u
     WHERE i.status IN ('posted', 'paid') AND r.rate IS NOT NULL AND i.invoice_date <= p_date AND u.open > 0
    UNION ALL
    SELECT account_map(CASE p.direction WHEN 'in' THEN 'receivable' ELSE 'payable' END), p.partner_id,
           (CASE p.direction WHEN 'in' THEN -1 ELSE 1 END)
             * (round(u.open * r.rate, 2) - round(u.open * p.fx_rate, 2))
      FROM t_payments p JOIN rates r ON r.code = p.currency
      CROSS JOIN LATERAL (SELECT p.amount + p.wht_amount - COALESCE((
            SELECT sum(a.amount) FROM t_payment_allocations a WHERE a.payment_id = p.id AND a.applied_date <= p_date), 0) AS open) u
     WHERE p.status = 'posted' AND r.rate IS NOT NULL AND p.payment_date <= p_date AND u.open > 0
    UNION ALL
    SELECT b.gl_account_id, NULL,
           round(COALESCE(sum(l.fc_amount), 0) * r.rate, 2) - COALESCE(sum(l.debit - l.credit), 0)
      FROM m_bank_accounts b JOIN rates r ON r.code = b.currency
      JOIN t_journal_lines l ON l.account_id = b.gl_account_id
      JOIN t_journals j ON j.id = l.journal_id AND j.status IN ('posted', 'reversed') AND j.journal_date <= p_date
     WHERE r.rate IS NOT NULL
     GROUP BY b.gl_account_id, r.rate),
  grouped AS (SELECT account_id, partner_id, sum(delta) AS delta FROM deltas GROUP BY account_id, partner_id HAVING sum(delta) <> 0)
  SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'partner_id', partner_id, 'amount', delta, 'memo', 'Revaluasi kurs')),
         COALESCE(sum(delta), 0)
    INTO v_lines, v_net FROM grouped;

  IF v_lines IS NULL THEN
    RETURN jsonb_build_object('lines', 0);
  END IF;
  v_lines := v_lines || jsonb_build_object('account_id', account_map(CASE WHEN v_net > 0 THEN 'fx_gain' ELSE 'fx_loss' END), 'amount', -v_net);
  v_jid := gl_create('fx_reval', p_date, 'Revaluasi kurs ' || to_char(p_date, 'DD/MM/YYYY'), NULL, 'fx_reval', NULL, v_lines);
  v_rev := gl_reverse(v_jid, p_date + 1, 'Pembalik revaluasi kurs ' || to_char(p_date, 'DD/MM/YYYY'));
  RETURN jsonb_build_object('lines', jsonb_array_length(v_lines), 'net', v_net, 'journal_id', v_jid, 'reversal_id', v_rev);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.general_ledger(bigint, date, date, bigint), public.bank_balances(date), public.asset_register_summary(),
  public.cash_month_end(date, integer), public.partner_payable_exposure(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.general_ledger(bigint, date, date, bigint), public.bank_balances(date), public.asset_register_summary(),
  public.cash_month_end(date, integer), public.partner_payable_exposure(bigint) TO authenticated;
