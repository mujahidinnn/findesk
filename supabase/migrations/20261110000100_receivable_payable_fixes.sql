
ALTER TABLE public.t_payment_allocations ADD COLUMN reclass_journal_id bigint REFERENCES public.t_journals;

CREATE OR REPLACE FUNCTION public.allocate_payment(p_payment_id bigint, p_invoice_id bigint, p_amount numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
  inv t_invoices;
  v_id bigint;
  v_date date;
  v_sign integer;
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_payment_id FOR UPDATE;
  IF pay.id IS NULL OR NOT has_permission(doc_feature(pay.direction), 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF pay.status <> 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  SELECT * INTO inv FROM t_invoices WHERE id = p_invoice_id;
  IF COALESCE(p_amount, 0) <= 0 OR inv.id IS NULL OR NOT payment_target_ok(pay.direction, inv.doc_type) THEN
    RAISE EXCEPTION 'ALLOCATION_INVALID' USING errcode = 'P0001';
  END IF;
  IF pay.allocated_amount + p_amount > pay.amount + pay.wht_amount THEN
    RAISE EXCEPTION 'OVER_ALLOCATED' USING errcode = 'P0001';
  END IF;
  v_date := greatest(company_today(), pay.payment_date);
  PERFORM posting_period(company_today());
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount, applied_date)
  VALUES (p_payment_id, p_invoice_id, p_amount, v_date)
  ON CONFLICT (payment_id, invoice_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'DUPLICATE' USING errcode = 'P0001';
  END IF;
  PERFORM apply_allocation(v_id);
  IF doc_feature(inv.doc_type) <> doc_feature(pay.direction) THEN
    v_sign := CASE pay.direction WHEN 'in' THEN 1 ELSE -1 END;
    UPDATE t_payment_allocations SET reclass_journal_id = gl_create(
      CASE pay.direction WHEN 'in' THEN 'payment_in' ELSE 'payment_out' END, v_date,
      'Alokasi refund ' || COALESCE(inv.doc_no, ''), pay.doc_no, 'payment_allocation', v_id,
      jsonb_build_array(
        jsonb_build_object('account_id', account_map(CASE pay.direction WHEN 'in' THEN 'receivable' ELSE 'payable' END),
                           'amount', v_sign * round(p_amount * pay.fx_rate, 2), 'partner_id', pay.partner_id,
                           'currency', pay.currency, 'fc_amount', v_sign * p_amount),
        jsonb_build_object('account_id', account_map(CASE pay.direction WHEN 'in' THEN 'payable' ELSE 'receivable' END),
                           'amount', -v_sign * round(p_amount * pay.fx_rate, 2), 'partner_id', pay.partner_id,
                           'currency', pay.currency, 'fc_amount', -v_sign * p_amount)))
     WHERE id = v_id;
  END IF;
  UPDATE t_payments SET allocated_amount = allocated_amount + p_amount WHERE id = p_payment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.void_payment(p_id bigint, p_reason text, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
  a t_payment_allocations;
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_id FOR UPDATE;
  IF pay.id IS NULL OR NOT has_permission(doc_feature(pay.direction), 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF pay.status <> 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_bank_statement_lines WHERE journal_line_id IN (SELECT id FROM t_journal_lines WHERE journal_id = pay.journal_id)) THEN
    RAISE EXCEPTION 'RECONCILED' USING errcode = 'P0001';
  END IF;
  FOR a IN SELECT * FROM t_payment_allocations WHERE payment_id = p_id LOOP
    IF a.fx_journal_id IS NOT NULL THEN
      PERFORM gl_reverse(a.fx_journal_id, p_date, NULL);
    END IF;
    IF a.reclass_journal_id IS NOT NULL THEN
      PERFORM gl_reverse(a.reclass_journal_id, p_date, NULL);
    END IF;
    PERFORM unapply_from_invoice(a.invoice_id, a.amount);
  END LOOP;
  DELETE FROM t_payment_allocations WHERE payment_id = p_id;
  UPDATE t_payments SET status = 'void', void_reason = p_reason, allocated_amount = 0,
         void_journal_id = gl_reverse(pay.journal_id, p_date, 'Batal ' || pay.doc_no)
   WHERE id = p_id;
END;
$$;

DROP FUNCTION public.apply_credit_note(bigint, bigint, numeric);
CREATE FUNCTION public.apply_credit_note(p_note_id bigint, p_invoice_id bigint, p_amount numeric, p_date date DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_date date := COALESCE(p_date, company_today());
BEGIN
  IF NOT has_permission(doc_feature((SELECT doc_type FROM t_invoices WHERE id = p_note_id)), 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF COALESCE(p_amount, 0) <= 0
     OR v_date < (SELECT greatest(max(invoice_date), 'epoch') FROM t_invoices WHERE id IN (p_note_id, p_invoice_id)) THEN
    RAISE EXCEPTION 'INVALID' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(v_date);
  RETURN apply_note_internal(p_note_id, p_invoice_id, p_amount, v_date);
END;
$$;

CREATE FUNCTION public.unapply_credit_note(p_application_id bigint, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a t_note_applications;
BEGIN
  SELECT * INTO a FROM t_note_applications WHERE id = p_application_id FOR UPDATE;
  IF a.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0002';
  END IF;
  IF NOT has_permission(doc_feature((SELECT doc_type FROM t_invoices WHERE id = a.note_id)), 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF a.fx_journal_id IS NOT NULL THEN
    PERFORM gl_reverse(a.fx_journal_id, p_date, NULL);
  END IF;
  PERFORM unapply_from_invoice(a.note_id, a.amount);
  PERFORM unapply_from_invoice(a.invoice_id, a.amount);
  DELETE FROM t_note_applications WHERE id = a.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_tax_invoice_no(p_id bigint, p_no text, p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
BEGIN
  SELECT * INTO inv FROM t_invoices WHERE id = p_id FOR UPDATE;
  IF inv.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0002';
  END IF;
  IF NOT (has_permission('tax', 'update') OR has_permission(doc_feature(inv.doc_type), 'update')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF inv.status = 'void' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  UPDATE t_invoices SET tax_invoice_no = NULLIF(trim(p_no), ''), tax_invoice_date = p_date WHERE id = p_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.apply_credit_note(bigint, bigint, numeric, date), public.unapply_credit_note(bigint, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_credit_note(bigint, bigint, numeric, date), public.unapply_credit_note(bigint, date) TO authenticated;
