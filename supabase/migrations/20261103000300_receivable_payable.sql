
CREATE TABLE public.t_invoices (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_type text NOT NULL CHECK (doc_type IN ('sales_invoice', 'sales_credit', 'purchase_bill', 'purchase_debit')),
    doc_no text UNIQUE,
    partner_id bigint NOT NULL REFERENCES public.m_partners,
    invoice_date date NOT NULL DEFAULT public.company_today(),
    due_date date,
    term_id bigint REFERENCES public.m_payment_terms,
    currency text NOT NULL DEFAULT 'IDR' REFERENCES public.m_currencies ON UPDATE CASCADE,
    fx_rate numeric(18,6) NOT NULL DEFAULT 1 CHECK (fx_rate > 0),
    reference text,
    tax_invoice_no text,
    tax_invoice_date date,
    original_invoice_id bigint REFERENCES public.t_invoices,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects,
    subtotal numeric(18,2) NOT NULL DEFAULT 0,
    discount_total numeric(18,2) NOT NULL DEFAULT 0,
    tax_total numeric(18,2) NOT NULL DEFAULT 0,
    wht_total numeric(18,2) NOT NULL DEFAULT 0,
    total numeric(18,2) NOT NULL DEFAULT 0,
    paid_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'posted', 'paid', 'void')),
    journal_id bigint REFERENCES public.t_journals,
    void_journal_id bigint REFERENCES public.t_journals,
    void_reason text,
    reject_reason text,
    note text,
    attachment_path text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    submitted_at timestamptz,
    approved_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    posted_at timestamptz,
    posted_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (paid_amount <= total OR status = 'draft'),
    CHECK (original_invoice_id IS NULL OR doc_type IN ('sales_credit', 'purchase_debit'))
);
CREATE INDEX t_invoices_partner_idx ON public.t_invoices (partner_id, status);
CREATE INDEX t_invoices_type_idx ON public.t_invoices (doc_type, invoice_date);

CREATE TABLE public.t_invoice_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id bigint NOT NULL REFERENCES public.t_invoices ON DELETE CASCADE,
    line_no integer NOT NULL DEFAULT 0,
    item_id bigint REFERENCES public.m_items,
    description text,
    account_id bigint REFERENCES public.m_accounts,
    qty numeric(18,4) NOT NULL DEFAULT 1 CHECK (qty > 0),
    unit_price numeric(18,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
    discount numeric(18,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    tax_id bigint REFERENCES public.m_taxes,
    wht_tax_id bigint REFERENCES public.m_taxes,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects,
    line_subtotal numeric(18,2) NOT NULL DEFAULT 0,
    tax_base numeric(18,2) NOT NULL DEFAULT 0,
    tax_amount numeric(18,2) NOT NULL DEFAULT 0,
    wht_amount numeric(18,2) NOT NULL DEFAULT 0,
    CHECK (item_id IS NOT NULL OR account_id IS NOT NULL)
);
CREATE INDEX t_invoice_lines_invoice_idx ON public.t_invoice_lines (invoice_id);

CREATE TABLE public.t_payments (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    direction text NOT NULL CHECK (direction IN ('in', 'out')),
    doc_no text UNIQUE,
    partner_id bigint NOT NULL REFERENCES public.m_partners,
    payment_date date NOT NULL DEFAULT public.company_today(),
    bank_account_id bigint NOT NULL REFERENCES public.m_bank_accounts,
    currency text NOT NULL DEFAULT 'IDR' REFERENCES public.m_currencies ON UPDATE CASCADE,
    fx_rate numeric(18,6) NOT NULL DEFAULT 1 CHECK (fx_rate > 0),
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    wht_tax_id bigint REFERENCES public.m_taxes,
    wht_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (wht_amount >= 0),
    wht_slip_no text,
    allocated_amount numeric(18,2) NOT NULL DEFAULT 0,
    reference text,
    note text,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'posted', 'void')),
    journal_id bigint REFERENCES public.t_journals,
    void_journal_id bigint REFERENCES public.t_journals,
    void_reason text,
    reject_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    submitted_at timestamptz,
    approved_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    posted_at timestamptz,
    posted_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((wht_amount > 0) = (wht_tax_id IS NOT NULL)),
    CHECK (direction = 'in' OR wht_amount = 0)
);
CREATE INDEX t_payments_partner_idx ON public.t_payments (partner_id, status);

CREATE TABLE public.t_payment_allocations (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_id bigint NOT NULL REFERENCES public.t_payments ON DELETE CASCADE,
    invoice_id bigint NOT NULL REFERENCES public.t_invoices,
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    applied_date date,
    fx_journal_id bigint REFERENCES public.t_journals,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_id, invoice_id)
);
CREATE INDEX t_payment_allocations_invoice_idx ON public.t_payment_allocations (invoice_id);

CREATE TABLE public.t_note_applications (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    note_id bigint NOT NULL REFERENCES public.t_invoices,
    invoice_id bigint NOT NULL REFERENCES public.t_invoices,
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    applied_date date NOT NULL DEFAULT public.company_today(),
    fx_journal_id bigint REFERENCES public.t_journals,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL
);
CREATE INDEX t_note_applications_note_idx ON public.t_note_applications (note_id);
CREATE INDEX t_note_applications_invoice_idx ON public.t_note_applications (invoice_id);

CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON public.t_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_payments_updated_at BEFORE UPDATE ON public.t_payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_audit_invoices AFTER UPDATE OF status ON public.t_invoices
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('invoice');
CREATE TRIGGER trg_audit_payments AFTER UPDATE OF status ON public.t_payments
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('payment');

-- API callers edit only drafts; status changes are RPCs (which run as the owner and skip this).
CREATE FUNCTION public.guard_draft_doc() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND OLD.status <> 'draft' THEN
    RAISE EXCEPTION 'DOC_LOCKED' USING errcode = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
CREATE TRIGGER trg_guard_invoice BEFORE UPDATE OR DELETE ON public.t_invoices FOR EACH ROW EXECUTE FUNCTION public.guard_draft_doc();
CREATE TRIGGER trg_guard_payment BEFORE UPDATE OR DELETE ON public.t_payments FOR EACH ROW EXECUTE FUNCTION public.guard_draft_doc();

CREATE FUNCTION public.doc_feature(p_doc_type text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT CASE WHEN p_doc_type LIKE 'sales%' OR p_doc_type = 'in' THEN 'receivable' ELSE 'payable' END $$;

CREATE FUNCTION public.doc_sign(p_doc_type text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT CASE WHEN p_doc_type IN ('sales_invoice', 'purchase_debit') THEN 1 ELSE -1 END $$;

CREATE FUNCTION public.doc_control_account(p_doc_type text) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$ SELECT account_map(CASE WHEN p_doc_type LIKE 'sales%' THEN 'receivable' ELSE 'payable' END) $$;

CREATE FUNCTION public.invoice_defaults() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.currency = base_currency() THEN
    NEW.fx_rate := 1;
  END IF;
  IF NEW.due_date IS NULL OR (TG_OP = 'UPDATE' AND NEW.term_id IS DISTINCT FROM OLD.term_id AND NEW.due_date = OLD.due_date) THEN
    NEW.due_date := NEW.invoice_date + COALESCE((SELECT days FROM m_payment_terms WHERE id = NEW.term_id), 0);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_invoice_defaults BEFORE INSERT OR UPDATE OF invoice_date, due_date, term_id, currency, fx_rate ON public.t_invoices
  FOR EACH ROW EXECUTE FUNCTION public.invoice_defaults();

CREATE FUNCTION public.payment_defaults() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.currency = base_currency() THEN
    NEW.fx_rate := 1;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payment_defaults BEFORE INSERT OR UPDATE OF currency, fx_rate ON public.t_payments
  FOR EACH ROW EXECUTE FUNCTION public.payment_defaults();

-- The server, not the client, computes every line amount.
CREATE FUNCTION public.compute_invoice_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tax m_taxes;
  v_wht m_taxes;
BEGIN
  NEW.line_subtotal := round(NEW.qty * NEW.unit_price - NEW.discount, 2);
  IF NEW.line_subtotal < 0 THEN
    RAISE EXCEPTION 'LINE_NEGATIVE' USING errcode = '23514';
  END IF;
  NEW.tax_base := 0; NEW.tax_amount := 0; NEW.wht_amount := 0;
  IF NEW.tax_id IS NOT NULL THEN
    SELECT * INTO v_tax FROM m_taxes WHERE id = NEW.tax_id;
    IF v_tax.kind <> 'vat' THEN
      RAISE EXCEPTION 'TAX_KIND_INVALID' USING errcode = '23514';
    END IF;
    NEW.tax_base := round(NEW.line_subtotal * v_tax.dpp_factor, 2);
    NEW.tax_amount := round(NEW.tax_base * v_tax.rate / 100, 2);
  END IF;
  IF NEW.wht_tax_id IS NOT NULL THEN
    IF (SELECT doc_type FROM t_invoices WHERE id = NEW.invoice_id) LIKE 'sales%' THEN
      RAISE EXCEPTION 'WHT_SALES_AT_PAYMENT' USING errcode = '23514';
    END IF;
    SELECT * INTO v_wht FROM m_taxes WHERE id = NEW.wht_tax_id;
    IF v_wht.kind <> 'wht' THEN
      RAISE EXCEPTION 'TAX_KIND_INVALID' USING errcode = '23514';
    END IF;
    NEW.wht_amount := round(NEW.line_subtotal * v_wht.rate / 100, 2);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_compute_invoice_line BEFORE INSERT OR UPDATE ON public.t_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.compute_invoice_line();

CREATE FUNCTION public.invoice_recalc(p_id bigint) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  UPDATE t_invoices i SET subtotal = s.sub, discount_total = s.disc, tax_total = s.tax, wht_total = s.wht,
         total = s.sub + s.tax - s.wht
    FROM (SELECT COALESCE(sum(line_subtotal), 0) sub, COALESCE(sum(discount), 0) disc,
                 COALESCE(sum(tax_amount), 0) tax, COALESCE(sum(wht_amount), 0) wht
            FROM t_invoice_lines WHERE invoice_id = p_id) s
   WHERE i.id = p_id AND i.status = 'draft';
$$;

CREATE FUNCTION public.invoice_lines_changed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM invoice_recalc(COALESCE(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_invoice_lines_changed AFTER INSERT OR UPDATE OR DELETE ON public.t_invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.invoice_lines_changed();

CREATE FUNCTION public.can_edit_invoice(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_invoices i WHERE i.id = p_id AND i.status = 'draft'
                  AND (has_permission(doc_feature(i.doc_type), 'update')
                       OR (i.created_by = auth.uid() AND has_permission(doc_feature(i.doc_type), 'create'))));
$$;

CREATE FUNCTION public.can_edit_payment(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_payments p WHERE p.id = p_id AND p.status = 'draft'
                  AND (has_permission(doc_feature(p.direction), 'update')
                       OR (p.created_by = auth.uid() AND has_permission(doc_feature(p.direction), 'create'))));
$$;

CREATE FUNCTION public.settle_fx(p_invoice t_invoices, p_amount numeric, p_other_rate numeric, p_date date,
                                 p_source_type text, p_source_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_residue numeric := doc_sign(p_invoice.doc_type) * (round(p_amount * p_invoice.fx_rate, 2) - round(p_amount * p_other_rate, 2));
BEGIN
  IF v_residue = 0 THEN
    RETURN NULL;
  END IF;
  RETURN gl_create('fx_realized', p_date, 'Selisih kurs ' || p_invoice.doc_no, p_invoice.doc_no, p_source_type, p_source_id,
    jsonb_build_array(
      jsonb_build_object('account_id', doc_control_account(p_invoice.doc_type), 'amount', -v_residue,
                         'partner_id', p_invoice.partner_id, 'currency', p_invoice.currency, 'fc_amount', 0),
      jsonb_build_object('account_id', account_map(CASE WHEN v_residue > 0 THEN 'fx_loss' ELSE 'fx_gain' END), 'amount', v_residue)));
END;
$$;

CREATE FUNCTION public.apply_to_invoice(p_invoice_id bigint, p_amount numeric) RETURNS t_invoices
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
BEGIN
  SELECT * INTO inv FROM t_invoices WHERE id = p_invoice_id FOR UPDATE;
  IF inv.status NOT IN ('posted', 'paid') THEN
    RAISE EXCEPTION 'INVOICE_NOT_OPEN' USING errcode = 'P0001';
  END IF;
  IF inv.paid_amount + p_amount > inv.total THEN
    RAISE EXCEPTION 'EXCEEDS_OPEN' USING errcode = 'P0001';
  END IF;
  UPDATE t_invoices SET paid_amount = paid_amount + p_amount,
         status = CASE WHEN paid_amount + p_amount = total THEN 'paid' ELSE 'posted' END
   WHERE id = p_invoice_id RETURNING * INTO inv;
  RETURN inv;
END;
$$;

CREATE FUNCTION public.unapply_from_invoice(p_invoice_id bigint, p_amount numeric) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  UPDATE t_invoices SET paid_amount = paid_amount - p_amount, status = 'posted' WHERE id = p_invoice_id;
$$;

CREATE FUNCTION public.apply_note_internal(p_note_id bigint, p_invoice_id bigint, p_amount numeric, p_date date) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  n t_invoices;
  inv t_invoices;
  v_id bigint;
BEGIN
  SELECT * INTO n FROM t_invoices WHERE id = p_note_id;
  SELECT * INTO inv FROM t_invoices WHERE id = p_invoice_id;
  IF n.doc_type NOT IN ('sales_credit', 'purchase_debit')
     OR inv.doc_type <> (CASE n.doc_type WHEN 'sales_credit' THEN 'sales_invoice' ELSE 'purchase_bill' END) THEN
    RAISE EXCEPTION 'NOTE_TARGET_INVALID' USING errcode = 'P0001';
  END IF;
  IF n.partner_id <> inv.partner_id OR n.currency <> inv.currency THEN
    RAISE EXCEPTION 'NOTE_TARGET_INVALID' USING errcode = 'P0001';
  END IF;
  PERFORM apply_to_invoice(p_note_id, p_amount);
  inv := apply_to_invoice(p_invoice_id, p_amount);
  INSERT INTO t_note_applications (note_id, invoice_id, amount, applied_date)
  VALUES (p_note_id, p_invoice_id, p_amount, p_date) RETURNING id INTO v_id;
  UPDATE t_note_applications SET fx_journal_id = settle_fx(inv, p_amount, n.fx_rate, p_date, 'note_application', v_id) WHERE id = v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.invoice_post(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
  v_sales boolean;
  v_sign integer;
  v_lines jsonb;
  v_jid bigint;
  v_open numeric;
BEGIN
  SELECT * INTO inv FROM t_invoices WHERE id = p_id FOR UPDATE;
  v_sales := inv.doc_type LIKE 'sales%';
  v_sign := CASE WHEN inv.doc_type IN ('sales_invoice', 'purchase_bill') THEN 1 ELSE -1 END;
  inv.doc_no := next_doc_no(inv.doc_type, inv.invoice_date);

  WITH l AS (
    SELECT il.*, it.kind AS item_kind, it.unit_cost, it.inventory_account_id, it.cogs_account_id,
           COALESCE(il.account_id, CASE WHEN v_sales THEN it.revenue_account_id
                                        ELSE COALESCE(it.inventory_account_id, it.expense_account_id) END,
                    account_map(CASE WHEN v_sales THEN 'sales_revenue' ELSE 'purchase_expense' END)) AS acc
      FROM t_invoice_lines il LEFT JOIN m_items it ON it.id = il.item_id
     WHERE il.invoice_id = p_id),
  entries AS (
    SELECT doc_control_account(inv.doc_type) AS account_id,
           (CASE WHEN v_sales THEN 1 ELSE -1 END) * v_sign * round(inv.total * inv.fx_rate, 2) AS amount,
           inv.partner_id AS partner_id, NULL::bigint AS cost_center_id, NULL::bigint AS project_id,
           inv.currency AS currency, (CASE WHEN v_sales THEN 1 ELSE -1 END) * v_sign * inv.total AS fc_amount, NULL::text AS memo
    UNION ALL
    SELECT l.acc, (CASE WHEN v_sales THEN -1 ELSE 1 END) * v_sign * round(l.line_subtotal * inv.fx_rate, 2),
           NULL, COALESCE(l.cost_center_id, inv.cost_center_id), COALESCE(l.project_id, inv.project_id), NULL, NULL, l.description
      FROM l
    UNION ALL
    SELECT CASE WHEN v_sales THEN t.sales_account_id ELSE t.purchase_account_id END,
           (CASE WHEN v_sales THEN -1 ELSE 1 END) * v_sign * round(sum(l.tax_amount) * inv.fx_rate, 2),
           NULL, NULL, NULL, NULL, NULL, t.name
      FROM l JOIN m_taxes t ON t.id = l.tax_id GROUP BY t.id
    UNION ALL
    SELECT t.purchase_account_id, -v_sign * round(sum(l.wht_amount) * inv.fx_rate, 2), inv.partner_id, NULL, NULL, NULL, NULL, t.name
      FROM l JOIN m_taxes t ON t.id = l.wht_tax_id GROUP BY t.id
    UNION ALL
    SELECT x.account_id, x.amount, NULL, COALESCE(l.cost_center_id, inv.cost_center_id), NULL, NULL, NULL, 'HPP ' || COALESCE(l.description, '')
      FROM l CROSS JOIN LATERAL (VALUES (l.cogs_account_id, v_sign * round(l.qty * l.unit_cost, 2)),
                                        (l.inventory_account_id, -v_sign * round(l.qty * l.unit_cost, 2))) AS x(account_id, amount)
     WHERE v_sales AND l.item_kind = 'goods' AND l.cogs_account_id IS NOT NULL AND l.unit_cost > 0)
  SELECT jsonb_agg(to_jsonb(entries)) INTO v_lines FROM entries;

  v_jid := gl_create(inv.doc_type, inv.invoice_date,
                     (SELECT name FROM m_partners WHERE id = inv.partner_id) || COALESCE(' · ' || inv.reference, ''),
                     inv.doc_no, 'invoice', p_id, v_lines);
  UPDATE t_invoices SET doc_no = inv.doc_no, status = 'posted', journal_id = v_jid, posted_at = now(), posted_by = auth.uid()
   WHERE id = p_id;

  IF inv.original_invoice_id IS NOT NULL THEN
    SELECT total - paid_amount INTO v_open FROM t_invoices WHERE id = inv.original_invoice_id AND status = 'posted';
    IF COALESCE(v_open, 0) > 0 THEN
      PERFORM apply_note_internal(p_id, inv.original_invoice_id, least(v_open, inv.total), inv.invoice_date);
    END IF;
  END IF;
END;
$$;

CREATE FUNCTION public.partner_exposure(p_partner_id bigint) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(sum(doc_sign(doc_type) * round((total - paid_amount) * fx_rate, 2)), 0)
    FROM t_invoices WHERE partner_id = p_partner_id AND doc_type LIKE 'sales%' AND status = 'posted';
$$;

CREATE FUNCTION public.submit_invoice(p_id bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
  p m_partners;
  orig t_invoices;
  v_feature text;
  v_needs_approval boolean;
BEGIN
  SELECT * INTO inv FROM t_invoices WHERE id = p_id FOR UPDATE;
  IF inv.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0001';
  END IF;
  v_feature := doc_feature(inv.doc_type);
  IF NOT (has_permission(v_feature, 'update') OR (inv.created_by = auth.uid() AND has_permission(v_feature, 'create'))) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF inv.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  PERFORM invoice_recalc(p_id);
  SELECT * INTO inv FROM t_invoices WHERE id = p_id;
  IF NOT EXISTS (SELECT 1 FROM t_invoice_lines WHERE invoice_id = p_id) OR inv.total <= 0 THEN
    RAISE EXCEPTION 'INVOICE_EMPTY' USING errcode = 'P0001';
  END IF;
  SELECT * INTO p FROM m_partners WHERE id = inv.partner_id;
  IF NOT p.is_active OR (v_feature = 'receivable' AND NOT p.is_customer) OR (v_feature = 'payable' AND NOT p.is_vendor) THEN
    RAISE EXCEPTION 'PARTNER_INVALID' USING errcode = 'P0001';
  END IF;
  IF inv.original_invoice_id IS NOT NULL THEN
    SELECT * INTO orig FROM t_invoices WHERE id = inv.original_invoice_id;
    IF orig.partner_id <> inv.partner_id OR orig.currency <> inv.currency OR orig.status NOT IN ('posted', 'paid')
       OR orig.doc_type <> (CASE inv.doc_type WHEN 'sales_credit' THEN 'sales_invoice' ELSE 'purchase_bill' END) THEN
      RAISE EXCEPTION 'NOTE_TARGET_INVALID' USING errcode = 'P0001';
    END IF;
  END IF;
  PERFORM posting_period(inv.invoice_date);

  v_needs_approval := CASE
    WHEN inv.doc_type = 'purchase_bill' THEN round(inv.total * inv.fx_rate, 2) >= (SELECT approval_threshold FROM m_settings WHERE id = 1)
    WHEN inv.doc_type = 'sales_invoice' THEN p.credit_limit > 0 AND partner_exposure(p.id) + round(inv.total * inv.fx_rate, 2) > p.credit_limit
    ELSE false END;
  IF v_needs_approval THEN
    UPDATE t_invoices SET status = 'submitted', submitted_at = now(), reject_reason = NULL WHERE id = p_id;
    PERFORM notify_users('approval', 'update', CASE WHEN v_feature = 'payable' THEN 'Tagihan pemasok menunggu persetujuan'
                                                     ELSE 'Invoice melewati batas kredit' END, p.name, '/approvals');
    RETURN 'submitted';
  END IF;
  PERFORM invoice_post(p_id);
  RETURN 'posted';
END;
$$;

CREATE FUNCTION public.decide_invoice(p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
BEGIN
  IF NOT has_permission('approval', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO inv FROM t_invoices WHERE id = p_id FOR UPDATE;
  IF inv.status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF inv.created_by = auth.uid() THEN
    RAISE EXCEPTION 'SELF_APPROVAL' USING errcode = '42501';
  END IF;
  IF p_approve THEN
    UPDATE t_invoices SET approved_by = auth.uid() WHERE id = p_id;
    PERFORM invoice_post(p_id);
  ELSE
    IF COALESCE(trim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
    END IF;
    UPDATE t_invoices SET status = 'draft', reject_reason = p_reason WHERE id = p_id;
  END IF;
  PERFORM notify_user(inv.created_by, CASE WHEN p_approve THEN 'Dokumen disetujui' ELSE 'Dokumen ditolak' END,
                      COALESCE(p_reason, inv.reference), CASE WHEN inv.doc_type LIKE 'sales%' THEN '/sales/invoices' ELSE '/purchases/bills' END);
END;
$$;

CREATE FUNCTION public.void_invoice(p_id bigint, p_reason text, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
BEGIN
  SELECT * INTO inv FROM t_invoices WHERE id = p_id FOR UPDATE;
  IF inv.id IS NULL OR NOT has_permission(doc_feature(inv.doc_type), 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF inv.status <> 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF inv.paid_amount > 0 THEN
    RAISE EXCEPTION 'INVOICE_HAS_PAYMENTS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
  END IF;
  UPDATE t_invoices SET status = 'void', void_reason = p_reason,
         void_journal_id = gl_reverse(inv.journal_id, p_date, 'Batal ' || inv.doc_no)
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.set_tax_invoice_no(p_id bigint, p_no text, p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT (has_permission('tax', 'update') OR has_permission(doc_feature((SELECT doc_type FROM t_invoices WHERE id = p_id)), 'update')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  UPDATE t_invoices SET tax_invoice_no = NULLIF(trim(p_no), ''), tax_invoice_date = p_date WHERE id = p_id AND status <> 'void';
END;
$$;

CREATE FUNCTION public.apply_credit_note(p_note_id bigint, p_invoice_id bigint, p_amount numeric) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission(doc_feature((SELECT doc_type FROM t_invoices WHERE id = p_note_id)), 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'INVALID' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(company_today());
  RETURN apply_note_internal(p_note_id, p_invoice_id, p_amount, company_today());
END;
$$;

CREATE FUNCTION public.payment_target_ok(p_direction text, p_doc_type text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT CASE p_direction WHEN 'in' THEN p_doc_type IN ('sales_invoice', 'purchase_debit')
                                  ELSE p_doc_type IN ('purchase_bill', 'sales_credit') END $$;

CREATE FUNCTION public.apply_allocation(p_alloc_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a t_payment_allocations;
  pay t_payments;
  inv t_invoices;
BEGIN
  SELECT * INTO a FROM t_payment_allocations WHERE id = p_alloc_id;
  SELECT * INTO pay FROM t_payments WHERE id = a.payment_id;
  SELECT * INTO inv FROM t_invoices WHERE id = a.invoice_id;
  IF inv.partner_id <> pay.partner_id OR inv.currency <> pay.currency OR NOT payment_target_ok(pay.direction, inv.doc_type) THEN
    RAISE EXCEPTION 'ALLOCATION_INVALID' USING errcode = 'P0001';
  END IF;
  inv := apply_to_invoice(a.invoice_id, a.amount);
  UPDATE t_payment_allocations
     SET applied_date = COALESCE(applied_date, pay.payment_date),
         fx_journal_id = settle_fx(inv, a.amount, pay.fx_rate, greatest(pay.payment_date, COALESCE(applied_date, pay.payment_date)), 'payment_allocation', a.id)
   WHERE id = p_alloc_id;
END;
$$;

CREATE FUNCTION public.payment_post(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
  v_bank m_bank_accounts;
  v_sign integer;
  v_cross numeric;
  v_settle numeric;
  v_jid bigint;
  a record;
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_id FOR UPDATE;
  SELECT * INTO v_bank FROM m_bank_accounts WHERE id = pay.bank_account_id;
  v_sign := CASE pay.direction WHEN 'in' THEN 1 ELSE -1 END;
  v_settle := pay.amount + pay.wht_amount;
  SELECT COALESCE(sum(al.amount), 0) INTO v_cross FROM t_payment_allocations al JOIN t_invoices i ON i.id = al.invoice_id
   WHERE al.payment_id = p_id AND doc_feature(i.doc_type) <> doc_feature(pay.direction);
  pay.doc_no := next_doc_no(CASE pay.direction WHEN 'in' THEN 'payment_in' ELSE 'payment_out' END, pay.payment_date);

  v_jid := gl_create(CASE pay.direction WHEN 'in' THEN 'payment_in' ELSE 'payment_out' END, pay.payment_date,
    (SELECT name FROM m_partners WHERE id = pay.partner_id) || COALESCE(' · ' || pay.reference, ''), pay.doc_no, 'payment', p_id,
    jsonb_build_array(
      jsonb_build_object('account_id', v_bank.gl_account_id, 'amount', v_sign * round(pay.amount * pay.fx_rate, 2),
                         'currency', pay.currency, 'fc_amount', v_sign * pay.amount),
      jsonb_build_object('account_id', (SELECT sales_account_id FROM m_taxes WHERE id = pay.wht_tax_id),
                         'amount', round(pay.wht_amount * pay.fx_rate, 2), 'partner_id', pay.partner_id),
      jsonb_build_object('account_id', account_map(CASE pay.direction WHEN 'in' THEN 'receivable' ELSE 'payable' END),
                         'amount', -v_sign * round((v_settle - v_cross) * pay.fx_rate, 2), 'partner_id', pay.partner_id,
                         'currency', pay.currency, 'fc_amount', -v_sign * (v_settle - v_cross)),
      jsonb_build_object('account_id', account_map(CASE pay.direction WHEN 'in' THEN 'payable' ELSE 'receivable' END),
                         'amount', -v_sign * round(v_cross * pay.fx_rate, 2), 'partner_id', pay.partner_id,
                         'currency', pay.currency, 'fc_amount', -v_sign * v_cross)));
  UPDATE t_payments SET doc_no = pay.doc_no, status = 'posted', journal_id = v_jid, posted_at = now(), posted_by = auth.uid()
   WHERE id = p_id;
  FOR a IN SELECT id FROM t_payment_allocations WHERE payment_id = p_id ORDER BY id LOOP
    PERFORM apply_allocation(a.id);
  END LOOP;
END;
$$;

CREATE FUNCTION public.payment_check(p_id bigint) RETURNS t_payments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
  v_alloc numeric;
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_id;
  IF (SELECT currency FROM m_bank_accounts WHERE id = pay.bank_account_id) <> pay.currency THEN
    RAISE EXCEPTION 'CURRENCY_MISMATCH' USING errcode = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM m_partners WHERE id = pay.partner_id AND is_active) THEN
    RAISE EXCEPTION 'PARTNER_INVALID' USING errcode = 'P0001';
  END IF;
  IF pay.wht_tax_id IS NOT NULL AND (SELECT kind FROM m_taxes WHERE id = pay.wht_tax_id) <> 'wht' THEN
    RAISE EXCEPTION 'TAX_KIND_INVALID' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_payment_allocations a JOIN t_invoices i ON i.id = a.invoice_id
              WHERE a.payment_id = p_id AND (i.partner_id <> pay.partner_id OR i.currency <> pay.currency
                    OR i.status <> 'posted' OR NOT payment_target_ok(pay.direction, i.doc_type) OR a.amount > i.total - i.paid_amount)) THEN
    RAISE EXCEPTION 'ALLOCATION_INVALID' USING errcode = 'P0001';
  END IF;
  SELECT COALESCE(sum(amount), 0) INTO v_alloc FROM t_payment_allocations WHERE payment_id = p_id;
  IF v_alloc > pay.amount + pay.wht_amount THEN
    RAISE EXCEPTION 'OVER_ALLOCATED' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(pay.payment_date);
  UPDATE t_payments SET allocated_amount = v_alloc WHERE id = p_id RETURNING * INTO pay;
  RETURN pay;
END;
$$;

CREATE FUNCTION public.submit_payment(p_id bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_id FOR UPDATE;
  IF pay.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0001';
  END IF;
  IF NOT (has_permission(doc_feature(pay.direction), 'update')
          OR (pay.created_by = auth.uid() AND has_permission(doc_feature(pay.direction), 'create'))) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF pay.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  pay := payment_check(p_id);
  IF pay.direction = 'out' AND round(pay.amount * pay.fx_rate, 2) >= (SELECT approval_threshold FROM m_settings WHERE id = 1) THEN
    UPDATE t_payments SET status = 'submitted', submitted_at = now(), reject_reason = NULL WHERE id = p_id;
    PERFORM notify_users('approval', 'update', 'Pembayaran menunggu persetujuan',
                         (SELECT name FROM m_partners WHERE id = pay.partner_id), '/approvals');
    RETURN 'submitted';
  END IF;
  PERFORM payment_post(p_id);
  RETURN 'posted';
END;
$$;

CREATE FUNCTION public.decide_payment(p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
BEGIN
  IF NOT has_permission('approval', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO pay FROM t_payments WHERE id = p_id FOR UPDATE;
  IF pay.status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF pay.created_by = auth.uid() THEN
    RAISE EXCEPTION 'SELF_APPROVAL' USING errcode = '42501';
  END IF;
  IF p_approve THEN
    PERFORM payment_check(p_id);
    UPDATE t_payments SET approved_by = auth.uid() WHERE id = p_id;
    PERFORM payment_post(p_id);
  ELSE
    IF COALESCE(trim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
    END IF;
    UPDATE t_payments SET status = 'draft', reject_reason = p_reason WHERE id = p_id;
  END IF;
  PERFORM notify_user(pay.created_by, CASE WHEN p_approve THEN 'Pembayaran disetujui' ELSE 'Pembayaran ditolak' END,
                      COALESCE(p_reason, pay.reference), '/purchases/payments');
END;
$$;

CREATE FUNCTION public.allocate_payment(p_payment_id bigint, p_invoice_id bigint, p_amount numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  pay t_payments;
  v_id bigint;
  v_doc text := (SELECT doc_type FROM t_invoices WHERE id = p_invoice_id);
BEGIN
  SELECT * INTO pay FROM t_payments WHERE id = p_payment_id FOR UPDATE;
  IF pay.id IS NULL OR NOT has_permission(doc_feature(pay.direction), 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF pay.status <> 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 OR doc_feature(v_doc) <> doc_feature(pay.direction) THEN
    RAISE EXCEPTION 'ALLOCATION_INVALID' USING errcode = 'P0001';
  END IF;
  IF pay.allocated_amount + p_amount > pay.amount + pay.wht_amount THEN
    RAISE EXCEPTION 'OVER_ALLOCATED' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(company_today());
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount, applied_date)
  VALUES (p_payment_id, p_invoice_id, p_amount, greatest(company_today(), pay.payment_date))
  ON CONFLICT (payment_id, invoice_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'DUPLICATE' USING errcode = 'P0001';
  END IF;
  PERFORM apply_allocation(v_id);
  UPDATE t_payments SET allocated_amount = allocated_amount + p_amount WHERE id = p_payment_id;
END;
$$;

CREATE FUNCTION public.void_payment(p_id bigint, p_reason text, p_date date DEFAULT NULL) RETURNS void
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
    PERFORM unapply_from_invoice(a.invoice_id, a.amount);
  END LOOP;
  DELETE FROM t_payment_allocations WHERE payment_id = p_id;
  UPDATE t_payments SET status = 'void', void_reason = p_reason, allocated_amount = 0,
         void_journal_id = gl_reverse(pay.journal_id, p_date, 'Batal ' || pay.doc_no)
   WHERE id = p_id;
END;
$$;

ALTER TABLE public.t_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_note_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY invoices_select ON public.t_invoices FOR SELECT TO authenticated
  USING (public.has_permission(public.doc_feature(doc_type), 'read') OR (SELECT public.has_permission('approval', 'read'))
         OR (SELECT public.has_permission('tax', 'read')));
CREATE POLICY invoices_insert ON public.t_invoices FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(public.doc_feature(doc_type), 'create') AND status = 'draft');
CREATE POLICY invoices_update ON public.t_invoices FOR UPDATE TO authenticated
  USING (public.can_edit_invoice(id)) WITH CHECK (status = 'draft');
CREATE POLICY invoices_delete ON public.t_invoices FOR DELETE TO authenticated
  USING (status = 'draft' AND (public.has_permission(public.doc_feature(doc_type), 'delete') OR created_by = (SELECT auth.uid())));
CREATE POLICY invoice_lines_select ON public.t_invoice_lines FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_invoices i WHERE i.id = invoice_id));
CREATE POLICY invoice_lines_write ON public.t_invoice_lines FOR ALL TO authenticated
  USING (public.can_edit_invoice(invoice_id)) WITH CHECK (public.can_edit_invoice(invoice_id));

CREATE POLICY payments_select ON public.t_payments FOR SELECT TO authenticated
  USING (public.has_permission(public.doc_feature(direction), 'read') OR (SELECT public.has_permission('approval', 'read')));
CREATE POLICY payments_insert ON public.t_payments FOR INSERT TO authenticated
  WITH CHECK (public.has_permission(public.doc_feature(direction), 'create') AND status = 'draft');
CREATE POLICY payments_update ON public.t_payments FOR UPDATE TO authenticated
  USING (public.can_edit_payment(id)) WITH CHECK (status = 'draft');
CREATE POLICY payments_delete ON public.t_payments FOR DELETE TO authenticated
  USING (status = 'draft' AND (public.has_permission(public.doc_feature(direction), 'delete') OR created_by = (SELECT auth.uid())));
CREATE POLICY allocations_select ON public.t_payment_allocations FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_payments p WHERE p.id = payment_id));
CREATE POLICY allocations_write ON public.t_payment_allocations FOR ALL TO authenticated
  USING (public.can_edit_payment(payment_id)) WITH CHECK (public.can_edit_payment(payment_id));
CREATE POLICY note_applications_select ON public.t_note_applications FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_invoices i WHERE i.id = note_id));

REVOKE INSERT, UPDATE ON public.t_invoices, public.t_invoice_lines, public.t_payments, public.t_payment_allocations FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.t_note_applications FROM authenticated;
GRANT INSERT (doc_type, partner_id, invoice_date, due_date, term_id, currency, fx_rate, reference, tax_invoice_no, tax_invoice_date,
              original_invoice_id, cost_center_id, project_id, note, attachment_path) ON public.t_invoices TO authenticated;
GRANT UPDATE (partner_id, invoice_date, due_date, term_id, currency, fx_rate, reference, tax_invoice_no, tax_invoice_date,
              original_invoice_id, cost_center_id, project_id, note, attachment_path) ON public.t_invoices TO authenticated;
GRANT INSERT (invoice_id, line_no, item_id, description, account_id, qty, unit_price, discount, tax_id, wht_tax_id, cost_center_id, project_id),
      UPDATE (line_no, item_id, description, account_id, qty, unit_price, discount, tax_id, wht_tax_id, cost_center_id, project_id)
  ON public.t_invoice_lines TO authenticated;
GRANT INSERT (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount, wht_tax_id, wht_amount, wht_slip_no, reference, note),
      UPDATE (partner_id, payment_date, bank_account_id, currency, fx_rate, amount, wht_tax_id, wht_amount, wht_slip_no, reference, note)
  ON public.t_payments TO authenticated;
GRANT INSERT (payment_id, invoice_id, amount), UPDATE (amount) ON public.t_payment_allocations TO authenticated;

-- Attachments (bills, receipts of expense claims): private bucket, any staff member with access.
-- ponytail: one shared folder space, readable by any staff member who knows the path; split per document type
-- (and check ownership for expense receipts) if attachments ever need their own permissions.
DROP POLICY IF EXISTS attachments_read ON storage.objects;
CREATE POLICY attachments_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'attachments' AND (SELECT public.has_any_access()));
DROP POLICY IF EXISTS attachments_insert ON storage.objects;
CREATE POLICY attachments_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'attachments' AND (SELECT public.has_any_access()));
