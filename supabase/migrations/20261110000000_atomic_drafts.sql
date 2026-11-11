-- Atomic draft saves: header + lines in one transaction. SECURITY INVOKER, so RLS and column grants apply exactly as
-- they do for direct table writes; the functions only add the all-or-nothing replacement of the lines.
-- p_id omitted/NULL creates the draft, otherwise it replaces the header fields and every line of that draft.
-- p_header carries every draft column (a missing key is NULL, so a NOT NULL column without it is refused).

CREATE FUNCTION public.draft_target(p_table text, p_id bigint) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_status text;
BEGIN
  EXECUTE format('SELECT status FROM public.%I WHERE id = $1', p_table) INTO v_status USING p_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0002'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001'; END IF;
END;
$$;

CREATE FUNCTION public.save_journal_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_journals (journal_date, kind, memo, reference)
    SELECT h.journal_date, h.kind, h.memo, h.reference FROM jsonb_populate_record(NULL::t_journals, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_journals', v_id);
    UPDATE t_journals t SET journal_date = h.journal_date, kind = h.kind, memo = h.memo, reference = h.reference
      FROM jsonb_populate_record(NULL::t_journals, p_header) h WHERE t.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501'; END IF;
    DELETE FROM t_journal_lines WHERE journal_id = v_id;
  END IF;
  INSERT INTO t_journal_lines (journal_id, line_no, account_id, debit, credit, memo, cost_center_id, project_id)
  SELECT v_id, e.n, l.account_id, COALESCE(l.debit, 0), COALESCE(l.credit, 0), l.memo, l.cost_center_id, l.project_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]')) WITH ORDINALITY e(v, n),
         LATERAL jsonb_populate_record(NULL::t_journal_lines, e.v) l;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.save_invoice_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_invoices (doc_type, partner_id, invoice_date, due_date, term_id, currency, fx_rate, reference, tax_invoice_no,
                            tax_invoice_date, original_invoice_id, cost_center_id, project_id, note, attachment_path)
    SELECT h.doc_type, h.partner_id, h.invoice_date, h.due_date, h.term_id, h.currency, h.fx_rate, h.reference, h.tax_invoice_no,
           h.tax_invoice_date, h.original_invoice_id, h.cost_center_id, h.project_id, h.note, h.attachment_path
      FROM jsonb_populate_record(NULL::t_invoices, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_invoices', v_id);
    UPDATE t_invoices t SET partner_id = h.partner_id, invoice_date = h.invoice_date, due_date = h.due_date, term_id = h.term_id,
           currency = h.currency, fx_rate = h.fx_rate, reference = h.reference, tax_invoice_no = h.tax_invoice_no,
           tax_invoice_date = h.tax_invoice_date, original_invoice_id = h.original_invoice_id, cost_center_id = h.cost_center_id,
           project_id = h.project_id, note = h.note, attachment_path = h.attachment_path
      FROM jsonb_populate_record(NULL::t_invoices, p_header) h WHERE t.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501'; END IF;
    DELETE FROM t_invoice_lines WHERE invoice_id = v_id;
  END IF;
  INSERT INTO t_invoice_lines (invoice_id, line_no, item_id, description, account_id, qty, unit_price, discount, tax_id, wht_tax_id,
                               cost_center_id, project_id)
  SELECT v_id, e.n, l.item_id, l.description, l.account_id, l.qty, COALESCE(l.unit_price, 0), COALESCE(l.discount, 0), l.tax_id,
         l.wht_tax_id, l.cost_center_id, l.project_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]')) WITH ORDINALITY e(v, n),
         LATERAL jsonb_populate_record(NULL::t_invoice_lines, e.v) l;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.save_payment_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount, wht_tax_id, wht_amount,
                            wht_slip_no, reference, note)
    SELECT h.direction, h.partner_id, h.payment_date, h.bank_account_id, h.currency, h.fx_rate, h.amount, h.wht_tax_id,
           COALESCE(h.wht_amount, 0), h.wht_slip_no, h.reference, h.note
      FROM jsonb_populate_record(NULL::t_payments, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_payments', v_id);
    UPDATE t_payments t SET partner_id = h.partner_id, payment_date = h.payment_date, bank_account_id = h.bank_account_id,
           currency = h.currency, fx_rate = h.fx_rate, amount = h.amount, wht_tax_id = h.wht_tax_id,
           wht_amount = COALESCE(h.wht_amount, 0), wht_slip_no = h.wht_slip_no, reference = h.reference, note = h.note
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

CREATE FUNCTION public.save_cash_txn_draft(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, partner_id, payee, fx_rate, reference, description)
    SELECT h.direction, h.bank_account_id, h.txn_date, h.partner_id, h.payee, h.fx_rate, h.reference, h.description
      FROM jsonb_populate_record(NULL::t_cash_txns, p_header) h
    RETURNING id INTO v_id;
  ELSE
    PERFORM draft_target('t_cash_txns', v_id);
    UPDATE t_cash_txns t SET bank_account_id = h.bank_account_id, txn_date = h.txn_date, partner_id = h.partner_id, payee = h.payee,
           fx_rate = h.fx_rate, reference = h.reference, description = h.description
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

CREATE FUNCTION public.save_recurring_journal(p_header jsonb, p_lines jsonb, p_id bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := p_id;
BEGIN
  IF v_id IS NULL THEN
    INSERT INTO t_recurring_journals (name, memo, frequency, next_run, end_date, is_active)
    SELECT h.name, h.memo, h.frequency, h.next_run, h.end_date, COALESCE(h.is_active, true)
      FROM jsonb_populate_record(NULL::t_recurring_journals, p_header) h
    RETURNING id INTO v_id;
  ELSE
    UPDATE t_recurring_journals t SET name = h.name, memo = h.memo, frequency = h.frequency, next_run = h.next_run,
           end_date = h.end_date, is_active = COALESCE(h.is_active, true)
      FROM jsonb_populate_record(NULL::t_recurring_journals, p_header) h WHERE t.id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0002'; END IF;
    DELETE FROM t_recurring_journal_lines WHERE recurring_id = v_id;
  END IF;
  INSERT INTO t_recurring_journal_lines (recurring_id, account_id, debit, credit, memo, cost_center_id, project_id)
  SELECT v_id, l.account_id, COALESCE(l.debit, 0), COALESCE(l.credit, 0), l.memo, l.cost_center_id, l.project_id
    FROM jsonb_array_elements(COALESCE(p_lines, '[]')) e(v), LATERAL jsonb_populate_record(NULL::t_recurring_journal_lines, e.v) l;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.draft_target(text, bigint), public.save_journal_draft(jsonb, jsonb, bigint),
  public.save_invoice_draft(jsonb, jsonb, bigint), public.save_payment_draft(jsonb, jsonb, bigint),
  public.save_cash_txn_draft(jsonb, jsonb, bigint), public.save_recurring_journal(jsonb, jsonb, bigint) FROM PUBLIC, anon;
-- draft_target runs as the caller inside the save_* functions, so it needs the grant too; it only reads through RLS.
GRANT EXECUTE ON FUNCTION public.draft_target(text, bigint), public.save_journal_draft(jsonb, jsonb, bigint), public.save_invoice_draft(jsonb, jsonb, bigint),
  public.save_payment_draft(jsonb, jsonb, bigint), public.save_cash_txn_draft(jsonb, jsonb, bigint),
  public.save_recurring_journal(jsonb, jsonb, bigint) TO authenticated;
