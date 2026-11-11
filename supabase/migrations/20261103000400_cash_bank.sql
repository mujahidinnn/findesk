
CREATE TABLE public.t_cash_txns (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    direction text NOT NULL CHECK (direction IN ('in', 'out')),
    doc_no text UNIQUE,
    bank_account_id bigint NOT NULL REFERENCES public.m_bank_accounts,
    txn_date date NOT NULL DEFAULT public.company_today(),
    partner_id bigint REFERENCES public.m_partners,
    payee text,
    currency text NOT NULL DEFAULT 'IDR' REFERENCES public.m_currencies ON UPDATE CASCADE,
    fx_rate numeric(18,6) NOT NULL DEFAULT 1 CHECK (fx_rate > 0),
    total numeric(18,2) NOT NULL DEFAULT 0,
    reference text,
    description text,
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
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_cash_txns_bank_idx ON public.t_cash_txns (bank_account_id, txn_date);

CREATE TABLE public.t_cash_txn_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    txn_id bigint NOT NULL REFERENCES public.t_cash_txns ON DELETE CASCADE,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    description text,
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    tax_id bigint REFERENCES public.m_taxes,
    tax_base numeric(18,2) NOT NULL DEFAULT 0,
    tax_amount numeric(18,2) NOT NULL DEFAULT 0,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects
);
CREATE INDEX t_cash_txn_lines_txn_idx ON public.t_cash_txn_lines (txn_id);

CREATE TABLE public.t_bank_transfers (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_no text UNIQUE,
    transfer_date date NOT NULL DEFAULT public.company_today(),
    from_bank_id bigint NOT NULL REFERENCES public.m_bank_accounts,
    to_bank_id bigint NOT NULL REFERENCES public.m_bank_accounts,
    from_amount numeric(18,2) NOT NULL CHECK (from_amount > 0),
    to_amount numeric(18,2) NOT NULL CHECK (to_amount > 0),
    from_rate numeric(18,6) NOT NULL DEFAULT 1 CHECK (from_rate > 0),
    to_rate numeric(18,6) NOT NULL DEFAULT 1 CHECK (to_rate > 0),
    fee_amount numeric(18,2) NOT NULL DEFAULT 0 CHECK (fee_amount >= 0),
    reference text,
    note text,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'posted', 'void')),
    journal_id bigint REFERENCES public.t_journals,
    void_journal_id bigint REFERENCES public.t_journals,
    void_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    posted_at timestamptz,
    posted_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (from_bank_id <> to_bank_id)
);

CREATE TABLE public.t_expense_claims (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_no text UNIQUE,
    employee_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles,
    claim_date date NOT NULL DEFAULT public.company_today(),
    title text NOT NULL,
    total numeric(18,2) NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'paid', 'void')),
    journal_id bigint REFERENCES public.t_journals,
    payment_journal_id bigint REFERENCES public.t_journals,
    paid_from_bank_id bigint REFERENCES public.m_bank_accounts,
    paid_at date,
    reject_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    submitted_at timestamptz,
    approved_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    approved_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_expense_claims_employee_idx ON public.t_expense_claims (employee_id, status);

CREATE TABLE public.t_expense_claim_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    claim_id bigint NOT NULL REFERENCES public.t_expense_claims ON DELETE CASCADE,
    expense_date date NOT NULL,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    description text NOT NULL,
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects,
    receipt_path text
);
CREATE INDEX t_expense_claim_lines_claim_idx ON public.t_expense_claim_lines (claim_id);

CREATE TABLE public.t_bank_statements (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bank_account_id bigint NOT NULL REFERENCES public.m_bank_accounts,
    start_date date NOT NULL,
    statement_date date NOT NULL,
    opening_balance numeric(18,2) NOT NULL DEFAULT 0,
    closing_balance numeric(18,2) NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'finished')),
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    finished_at timestamptz,
    finished_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (statement_date >= start_date)
);

CREATE TABLE public.t_bank_statement_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    statement_id bigint NOT NULL REFERENCES public.t_bank_statements ON DELETE CASCADE,
    line_date date NOT NULL,
    description text,
    reference text,
    amount numeric(18,2) NOT NULL CHECK (amount <> 0),
    journal_line_id bigint UNIQUE REFERENCES public.t_journal_lines,
    matched_at timestamptz,
    matched_by uuid REFERENCES public.profiles ON DELETE SET NULL
);
CREATE INDEX t_bank_statement_lines_stmt_idx ON public.t_bank_statement_lines (statement_id);

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['t_cash_txns', 't_bank_transfers', 't_expense_claims', 't_bank_statements'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t);
    EXECUTE format('CREATE TRIGGER trg_audit_%1$s AFTER UPDATE OF status ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.audit_row_change(%1$L)', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['t_cash_txns', 't_bank_transfers', 't_expense_claims'] LOOP
    EXECUTE format('CREATE TRIGGER trg_guard_%1$s BEFORE UPDATE OR DELETE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.guard_draft_doc()', t);
  END LOOP;
END $$;

CREATE FUNCTION public.guard_statement() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND OLD.status <> 'open' THEN
    RAISE EXCEPTION 'DOC_LOCKED' USING errcode = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
CREATE TRIGGER trg_guard_statement BEFORE UPDATE OR DELETE ON public.t_bank_statements FOR EACH ROW EXECUTE FUNCTION public.guard_statement();

CREATE FUNCTION public.cash_txn_defaults() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.currency := (SELECT currency FROM m_bank_accounts WHERE id = NEW.bank_account_id);
  IF NEW.currency = base_currency() THEN
    NEW.fx_rate := 1;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_cash_txn_defaults BEFORE INSERT OR UPDATE OF bank_account_id, fx_rate ON public.t_cash_txns
  FOR EACH ROW EXECUTE FUNCTION public.cash_txn_defaults();

CREATE FUNCTION public.compute_cash_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tax m_taxes;
BEGIN
  NEW.tax_base := 0; NEW.tax_amount := 0;
  IF NEW.tax_id IS NOT NULL THEN
    SELECT * INTO v_tax FROM m_taxes WHERE id = NEW.tax_id;
    IF v_tax.kind <> 'vat' THEN
      RAISE EXCEPTION 'TAX_KIND_INVALID' USING errcode = '23514';
    END IF;
    NEW.tax_base := round(NEW.amount * v_tax.dpp_factor, 2);
    NEW.tax_amount := round(NEW.tax_base * v_tax.rate / 100, 2);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_compute_cash_line BEFORE INSERT OR UPDATE ON public.t_cash_txn_lines
  FOR EACH ROW EXECUTE FUNCTION public.compute_cash_line();

CREATE FUNCTION public.cash_lines_changed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := COALESCE(NEW.txn_id, OLD.txn_id);
BEGIN
  UPDATE t_cash_txns SET total = (SELECT COALESCE(sum(amount + tax_amount), 0) FROM t_cash_txn_lines WHERE txn_id = v_id)
   WHERE id = v_id AND status = 'draft';
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_cash_lines_changed AFTER INSERT OR UPDATE OR DELETE ON public.t_cash_txn_lines
  FOR EACH ROW EXECUTE FUNCTION public.cash_lines_changed();

CREATE FUNCTION public.expense_lines_changed() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint := COALESCE(NEW.claim_id, OLD.claim_id);
BEGIN
  UPDATE t_expense_claims SET total = (SELECT COALESCE(sum(amount), 0) FROM t_expense_claim_lines WHERE claim_id = v_id)
   WHERE id = v_id AND status = 'draft';
  RETURN NULL;
END;
$$;
CREATE TRIGGER trg_expense_lines_changed AFTER INSERT OR UPDATE OR DELETE ON public.t_expense_claim_lines
  FOR EACH ROW EXECUTE FUNCTION public.expense_lines_changed();

CREATE FUNCTION public.cash_txn_post(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  c t_cash_txns;
  v_sign integer;
  v_lines jsonb;
BEGIN
  SELECT * INTO c FROM t_cash_txns WHERE id = p_id FOR UPDATE;
  v_sign := CASE c.direction WHEN 'in' THEN 1 ELSE -1 END;
  c.doc_no := next_doc_no(CASE c.direction WHEN 'in' THEN 'cash_in' ELSE 'cash_out' END, c.txn_date);
  SELECT jsonb_agg(e) INTO v_lines FROM (
    SELECT jsonb_build_object('account_id', b.gl_account_id, 'amount', v_sign * round(c.total * c.fx_rate, 2),
                              'currency', c.currency, 'fc_amount', v_sign * c.total) e
      FROM m_bank_accounts b WHERE b.id = c.bank_account_id
    UNION ALL
    SELECT jsonb_build_object('account_id', l.account_id, 'amount', -v_sign * round(l.amount * c.fx_rate, 2), 'memo', l.description,
                              'partner_id', c.partner_id, 'cost_center_id', l.cost_center_id, 'project_id', l.project_id)
      FROM t_cash_txn_lines l WHERE l.txn_id = p_id
    UNION ALL
    SELECT jsonb_build_object('account_id', CASE c.direction WHEN 'in' THEN t.sales_account_id ELSE t.purchase_account_id END,
                              'amount', -v_sign * round(l.tax_amount * c.fx_rate, 2), 'memo', t.name)
      FROM t_cash_txn_lines l JOIN m_taxes t ON t.id = l.tax_id WHERE l.txn_id = p_id) x;
  UPDATE t_cash_txns
     SET doc_no = c.doc_no, status = 'posted', posted_at = now(), posted_by = auth.uid(),
         journal_id = gl_create(CASE c.direction WHEN 'in' THEN 'cash_in' ELSE 'cash_out' END, c.txn_date,
                                COALESCE(c.description, c.payee), c.doc_no, 'cash_txn', p_id, v_lines)
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.submit_cash_txn(p_id bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  c t_cash_txns;
BEGIN
  SELECT * INTO c FROM t_cash_txns WHERE id = p_id FOR UPDATE;
  IF c.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0001';
  END IF;
  IF NOT (has_permission('cash-bank', 'update') OR (c.created_by = auth.uid() AND has_permission('cash-bank', 'create'))) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF c.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF c.total <= 0 THEN
    RAISE EXCEPTION 'INVOICE_EMPTY' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_cash_txn_lines l JOIN m_accounts a ON a.id = l.account_id
              WHERE l.txn_id = p_id AND (a.is_control OR a.subtype IN ('cash', 'bank'))) THEN
    RAISE EXCEPTION 'CONTROL_ACCOUNT' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(c.txn_date);
  IF c.direction = 'out' AND round(c.total * c.fx_rate, 2) >= (SELECT approval_threshold FROM m_settings WHERE id = 1) THEN
    UPDATE t_cash_txns SET status = 'submitted', submitted_at = now(), reject_reason = NULL WHERE id = p_id;
    PERFORM notify_users('approval', 'update', 'Pengeluaran kas menunggu persetujuan', c.description, '/approvals');
    RETURN 'submitted';
  END IF;
  PERFORM cash_txn_post(p_id);
  RETURN 'posted';
END;
$$;

CREATE FUNCTION public.decide_cash_txn(p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  c t_cash_txns;
BEGIN
  IF NOT has_permission('approval', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO c FROM t_cash_txns WHERE id = p_id FOR UPDATE;
  IF c.status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF c.created_by = auth.uid() THEN
    RAISE EXCEPTION 'SELF_APPROVAL' USING errcode = '42501';
  END IF;
  IF p_approve THEN
    UPDATE t_cash_txns SET approved_by = auth.uid() WHERE id = p_id;
    PERFORM cash_txn_post(p_id);
  ELSE
    IF COALESCE(trim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
    END IF;
    UPDATE t_cash_txns SET status = 'draft', reject_reason = p_reason WHERE id = p_id;
  END IF;
  PERFORM notify_user(c.created_by, CASE WHEN p_approve THEN 'Pengeluaran kas disetujui' ELSE 'Pengeluaran kas ditolak' END,
                      COALESCE(p_reason, c.description), '/cash');
END;
$$;

CREATE FUNCTION public.journal_reconciled(p_journal_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_bank_statement_lines s JOIN t_journal_lines l ON l.id = s.journal_line_id WHERE l.journal_id = p_journal_id);
$$;

CREATE FUNCTION public.void_cash_txn(p_id bigint, p_reason text, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  c t_cash_txns;
BEGIN
  IF NOT has_permission('cash-bank', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO c FROM t_cash_txns WHERE id = p_id FOR UPDATE;
  IF c.status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
  END IF;
  IF journal_reconciled(c.journal_id) THEN
    RAISE EXCEPTION 'RECONCILED' USING errcode = 'P0001';
  END IF;
  UPDATE t_cash_txns SET status = 'void', void_reason = p_reason, void_journal_id = gl_reverse(c.journal_id, p_date, 'Batal ' || c.doc_no)
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.post_transfer(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  t t_bank_transfers;
  f m_bank_accounts;
  d m_bank_accounts;
  v_base text := base_currency();
  v_out numeric;
  v_in numeric;
  v_fee numeric;
BEGIN
  SELECT * INTO t FROM t_bank_transfers WHERE id = p_id FOR UPDATE;
  IF t.id IS NULL OR NOT (has_permission('cash-bank', 'update') OR (t.created_by = auth.uid() AND has_permission('cash-bank', 'create'))) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF t.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  SELECT * INTO f FROM m_bank_accounts WHERE id = t.from_bank_id;
  SELECT * INTO d FROM m_bank_accounts WHERE id = t.to_bank_id;
  IF f.currency = v_base THEN t.from_rate := 1; END IF;
  IF d.currency = v_base THEN t.to_rate := 1; END IF;
  IF f.currency = d.currency AND (t.from_amount <> t.to_amount OR t.from_rate <> t.to_rate) THEN
    RAISE EXCEPTION 'TRANSFER_AMOUNT_MISMATCH' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(t.transfer_date);
  v_out := round((t.from_amount + t.fee_amount) * t.from_rate, 2);
  v_fee := round(t.fee_amount * t.from_rate, 2);
  v_in := round(t.to_amount * t.to_rate, 2);
  t.doc_no := next_doc_no('transfer', t.transfer_date);
  UPDATE t_bank_transfers
     SET doc_no = t.doc_no, status = 'posted', from_rate = t.from_rate, to_rate = t.to_rate, posted_at = now(), posted_by = auth.uid(),
         journal_id = gl_create('transfer', t.transfer_date, COALESCE(t.note, f.name || ' → ' || d.name), t.doc_no, 'transfer', p_id,
           jsonb_build_array(
             jsonb_build_object('account_id', f.gl_account_id, 'amount', -v_out, 'currency', f.currency, 'fc_amount', -(t.from_amount + t.fee_amount)),
             jsonb_build_object('account_id', d.gl_account_id, 'amount', v_in, 'currency', d.currency, 'fc_amount', t.to_amount),
             jsonb_build_object('account_id', account_map('bank_fee'), 'amount', v_fee),
             jsonb_build_object('account_id', account_map(CASE WHEN v_out - v_fee - v_in > 0 THEN 'fx_loss' ELSE 'fx_gain' END),
                                'amount', v_out - v_fee - v_in)))
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.void_transfer(p_id bigint, p_reason text, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  t t_bank_transfers;
BEGIN
  IF NOT has_permission('cash-bank', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO t FROM t_bank_transfers WHERE id = p_id FOR UPDATE;
  IF t.status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
  END IF;
  IF journal_reconciled(t.journal_id) THEN
    RAISE EXCEPTION 'RECONCILED' USING errcode = 'P0001';
  END IF;
  UPDATE t_bank_transfers SET status = 'void', void_reason = p_reason, void_journal_id = gl_reverse(t.journal_id, p_date, 'Batal ' || t.doc_no)
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.submit_expense_claim(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  e t_expense_claims;
BEGIN
  SELECT * INTO e FROM t_expense_claims WHERE id = p_id FOR UPDATE;
  IF e.id IS NULL OR NOT ((e.employee_id = auth.uid() AND has_permission('expense', 'create')) OR has_permission('expense', 'update')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF e.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF e.total <= 0 THEN
    RAISE EXCEPTION 'INVOICE_EMPTY' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_expense_claim_lines l JOIN m_accounts a ON a.id = l.account_id
              WHERE l.claim_id = p_id AND (a.account_type <> 'expense' OR NOT a.is_postable)) THEN
    RAISE EXCEPTION 'EXPENSE_ACCOUNT_INVALID' USING errcode = 'P0001';
  END IF;
  UPDATE t_expense_claims SET status = 'submitted', submitted_at = now(), reject_reason = NULL,
         doc_no = COALESCE(doc_no, next_doc_no('expense', e.claim_date))
   WHERE id = p_id;
  PERFORM notify_users('approval', 'update', 'Reimburse menunggu persetujuan', e.title, '/approvals');
END;
$$;

CREATE FUNCTION public.decide_expense_claim(p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  e t_expense_claims;
  v_date date;
BEGIN
  IF NOT has_permission('approval', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO e FROM t_expense_claims WHERE id = p_id FOR UPDATE;
  IF e.status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF auth.uid() IN (e.employee_id, e.created_by) THEN
    RAISE EXCEPTION 'SELF_APPROVAL' USING errcode = '42501';
  END IF;
  IF NOT p_approve THEN
    IF COALESCE(trim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
    END IF;
    UPDATE t_expense_claims SET status = 'draft', reject_reason = p_reason WHERE id = p_id;
    PERFORM notify_user(e.employee_id, 'Reimburse ditolak', p_reason, '/expenses');
    RETURN;
  END IF;
  v_date := greatest(e.claim_date, (SELECT min(p.start_date) FROM m_periods p JOIN m_fiscal_years y ON y.id = p.fiscal_year_id
                                     WHERE p.status = 'open' AND y.status = 'open'));
  UPDATE t_expense_claims SET status = 'approved', approved_by = auth.uid(), approved_at = now(),
         journal_id = gl_create('expense', v_date, e.title || ' · ' || (SELECT full_name FROM profiles WHERE id = e.employee_id), e.doc_no,
           'expense_claim', p_id,
           (SELECT jsonb_agg(x) FROM (
              SELECT jsonb_build_object('account_id', account_id, 'amount', amount, 'memo', description,
                                        'cost_center_id', cost_center_id, 'project_id', project_id) x
                FROM t_expense_claim_lines WHERE claim_id = p_id
              UNION ALL SELECT jsonb_build_object('account_id', account_map('employee_payable'), 'amount', -e.total)) s))
   WHERE id = p_id;
  PERFORM notify_user(e.employee_id, 'Reimburse disetujui', e.title, '/expenses');
END;
$$;

CREATE FUNCTION public.pay_expense_claim(p_id bigint, p_bank_id bigint, p_date date DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  e t_expense_claims;
  b m_bank_accounts;
  v_date date := COALESCE(p_date, company_today());
BEGIN
  IF NOT has_permission('cash-bank', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO e FROM t_expense_claims WHERE id = p_id FOR UPDATE;
  IF e.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  SELECT * INTO b FROM m_bank_accounts WHERE id = p_bank_id AND is_active;
  IF b.id IS NULL OR b.currency <> base_currency() THEN
    RAISE EXCEPTION 'CURRENCY_MISMATCH' USING errcode = 'P0001';
  END IF;
  UPDATE t_expense_claims SET status = 'paid', paid_from_bank_id = p_bank_id, paid_at = v_date,
         payment_journal_id = gl_create('expense_payment', v_date, 'Bayar reimburse ' || e.doc_no, e.doc_no, 'expense_claim', p_id,
           jsonb_build_array(jsonb_build_object('account_id', account_map('employee_payable'), 'amount', e.total),
                             jsonb_build_object('account_id', b.gl_account_id, 'amount', -e.total, 'currency', b.currency, 'fc_amount', -e.total)))
   WHERE id = p_id;
  PERFORM notify_user(e.employee_id, 'Reimburse dibayar', e.title, '/expenses');
END;
$$;

CREATE FUNCTION public.bank_amount(p_line t_journal_lines, p_currency text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE WHEN p_currency = base_currency() THEN p_line.debit - p_line.credit ELSE COALESCE(p_line.fc_amount, 0) END;
$$;

CREATE FUNCTION public.statement_book_entries(p_statement_id bigint)
RETURNS TABLE (journal_line_id bigint, journal_date date, doc_no text, reference text, memo text, amount numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT l.id, j.journal_date, j.doc_no, j.reference, COALESCE(l.memo, j.memo), bank_amount(l, b.currency)
    FROM t_bank_statements s
    JOIN m_bank_accounts b ON b.id = s.bank_account_id
    JOIN t_journal_lines l ON l.account_id = b.gl_account_id
    JOIN t_journals j ON j.id = l.journal_id AND j.status IN ('posted', 'reversed')
   WHERE s.id = p_statement_id AND has_permission('reconcile', 'read') AND j.journal_date <= s.statement_date
     AND bank_amount(l, b.currency) <> 0
     AND NOT EXISTS (SELECT 1 FROM t_bank_statement_lines m WHERE m.journal_line_id = l.id)
   ORDER BY j.journal_date, l.id;
$$;

CREATE FUNCTION public.match_statement_line(p_line_id bigint, p_journal_line_id bigint DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  s t_bank_statements;
  sl t_bank_statement_lines;
BEGIN
  IF NOT has_permission('reconcile', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO sl FROM t_bank_statement_lines WHERE id = p_line_id FOR UPDATE;
  SELECT * INTO s FROM t_bank_statements WHERE id = sl.statement_id;
  IF s.status <> 'open' THEN
    RAISE EXCEPTION 'DOC_LOCKED' USING errcode = '42501';
  END IF;
  IF p_journal_line_id IS NULL THEN
    UPDATE t_bank_statement_lines SET journal_line_id = NULL, matched_at = NULL, matched_by = NULL WHERE id = p_line_id;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM statement_book_entries(s.id) e WHERE e.journal_line_id = p_journal_line_id AND e.amount = sl.amount) THEN
    RAISE EXCEPTION 'MATCH_INVALID' USING errcode = 'P0001';
  END IF;
  UPDATE t_bank_statement_lines SET journal_line_id = p_journal_line_id, matched_at = now(), matched_by = auth.uid() WHERE id = p_line_id;
END;
$$;

CREATE FUNCTION public.auto_match_statement(p_statement_id bigint) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  sl t_bank_statement_lines;
  v_jl bigint;
  v_count integer := 0;
BEGIN
  IF NOT has_permission('reconcile', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF (SELECT status FROM t_bank_statements WHERE id = p_statement_id) IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'DOC_LOCKED' USING errcode = '42501';
  END IF;
  FOR sl IN SELECT * FROM t_bank_statement_lines WHERE statement_id = p_statement_id AND journal_line_id IS NULL ORDER BY line_date, id LOOP
    SELECT e.journal_line_id INTO v_jl FROM statement_book_entries(p_statement_id) e
     WHERE e.amount = sl.amount AND abs(e.journal_date - sl.line_date) <= 5
     ORDER BY abs(e.journal_date - sl.line_date),
              (sl.reference IS NOT NULL AND (e.reference = sl.reference OR e.doc_no = sl.reference)) DESC, e.journal_line_id
     LIMIT 1;
    IF v_jl IS NOT NULL THEN
      UPDATE t_bank_statement_lines SET journal_line_id = v_jl, matched_at = now(), matched_by = auth.uid() WHERE id = sl.id;
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE FUNCTION public.book_statement_line(p_line_id bigint, p_account_id bigint, p_description text DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  sl t_bank_statement_lines;
  s t_bank_statements;
  b m_bank_accounts;
  v_txn bigint;
  v_jl bigint;
BEGIN
  IF NOT (has_permission('reconcile', 'update') AND has_permission('cash-bank', 'create')) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO sl FROM t_bank_statement_lines WHERE id = p_line_id FOR UPDATE;
  SELECT * INTO s FROM t_bank_statements WHERE id = sl.statement_id;
  SELECT * INTO b FROM m_bank_accounts WHERE id = s.bank_account_id;
  IF s.status <> 'open' OR sl.journal_line_id IS NOT NULL THEN
    RAISE EXCEPTION 'DOC_LOCKED' USING errcode = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM m_accounts WHERE id = p_account_id AND (is_control OR subtype IN ('cash', 'bank') OR NOT is_postable)) THEN
    RAISE EXCEPTION 'CONTROL_ACCOUNT' USING errcode = 'P0001';
  END IF;
  INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, fx_rate, reference, description)
  VALUES (CASE WHEN sl.amount > 0 THEN 'in' ELSE 'out' END, b.id, sl.line_date, COALESCE(fx_rate_on(b.currency, sl.line_date), 1),
          sl.reference, COALESCE(p_description, sl.description))
  RETURNING id INTO v_txn;
  INSERT INTO t_cash_txn_lines (txn_id, account_id, description, amount)
  VALUES (v_txn, p_account_id, COALESCE(p_description, sl.description), abs(sl.amount));
  PERFORM posting_period(sl.line_date);
  PERFORM cash_txn_post(v_txn);
  SELECT l.id INTO v_jl FROM t_journal_lines l JOIN t_cash_txns c ON c.journal_id = l.journal_id
   WHERE c.id = v_txn AND l.account_id = b.gl_account_id;
  UPDATE t_bank_statement_lines SET journal_line_id = v_jl, matched_at = now(), matched_by = auth.uid() WHERE id = p_line_id;
  RETURN v_txn;
END;
$$;

CREATE FUNCTION public.finish_statement(p_statement_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  s t_bank_statements;
BEGIN
  IF NOT has_permission('reconcile', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO s FROM t_bank_statements WHERE id = p_statement_id FOR UPDATE;
  IF s.status <> 'open' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_bank_statement_lines WHERE statement_id = p_statement_id AND journal_line_id IS NULL) THEN
    RAISE EXCEPTION 'STATEMENT_UNMATCHED' USING errcode = 'P0001';
  END IF;
  IF s.opening_balance + (SELECT COALESCE(sum(amount), 0) FROM t_bank_statement_lines WHERE statement_id = p_statement_id) <> s.closing_balance THEN
    RAISE EXCEPTION 'STATEMENT_UNBALANCED' USING errcode = 'P0001';
  END IF;
  UPDATE t_bank_statements SET status = 'finished', finished_at = now(), finished_by = auth.uid() WHERE id = p_statement_id;
END;
$$;

CREATE FUNCTION public.reopen_statement(p_statement_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('reconcile', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  UPDATE t_bank_statements SET status = 'open', finished_at = NULL, finished_by = NULL WHERE id = p_statement_id AND status = 'finished';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
END;
$$;

CREATE FUNCTION public.can_edit_cash_txn(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_cash_txns c WHERE c.id = p_id AND c.status = 'draft'
                  AND (has_permission('cash-bank', 'update') OR (c.created_by = auth.uid() AND has_permission('cash-bank', 'create'))));
$$;

CREATE FUNCTION public.can_see_claim(p_employee uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT p_employee = auth.uid() OR has_permission('expense-all', 'read') OR has_permission('approval', 'read');
$$;

CREATE FUNCTION public.can_edit_claim(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_expense_claims e WHERE e.id = p_id AND e.status = 'draft'
                  AND ((e.employee_id = auth.uid() AND has_permission('expense', 'create')) OR has_permission('expense', 'update')));
$$;

ALTER TABLE public.t_cash_txns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_cash_txn_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_bank_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_expense_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_expense_claim_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_bank_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_bank_statement_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY cash_select ON public.t_cash_txns FOR SELECT TO authenticated
  USING ((SELECT public.has_permission('cash-bank', 'read')) OR (SELECT public.has_permission('approval', 'read')));
CREATE POLICY cash_insert ON public.t_cash_txns FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('cash-bank', 'create')) AND status = 'draft');
CREATE POLICY cash_update ON public.t_cash_txns FOR UPDATE TO authenticated USING (public.can_edit_cash_txn(id)) WITH CHECK (status = 'draft');
CREATE POLICY cash_delete ON public.t_cash_txns FOR DELETE TO authenticated USING (public.can_edit_cash_txn(id));
CREATE POLICY cash_lines_select ON public.t_cash_txn_lines FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_cash_txns c WHERE c.id = txn_id));
CREATE POLICY cash_lines_write ON public.t_cash_txn_lines FOR ALL TO authenticated
  USING (public.can_edit_cash_txn(txn_id)) WITH CHECK (public.can_edit_cash_txn(txn_id));

CREATE POLICY transfers_select ON public.t_bank_transfers FOR SELECT TO authenticated USING ((SELECT public.has_permission('cash-bank', 'read')));
CREATE POLICY transfers_insert ON public.t_bank_transfers FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('cash-bank', 'create')) AND status = 'draft');
CREATE POLICY transfers_update ON public.t_bank_transfers FOR UPDATE TO authenticated
  USING (status = 'draft' AND ((SELECT public.has_permission('cash-bank', 'update')) OR created_by = (SELECT auth.uid())))
  WITH CHECK (status = 'draft');
CREATE POLICY transfers_delete ON public.t_bank_transfers FOR DELETE TO authenticated
  USING (status = 'draft' AND ((SELECT public.has_permission('cash-bank', 'delete')) OR created_by = (SELECT auth.uid())));

CREATE POLICY claims_select ON public.t_expense_claims FOR SELECT TO authenticated USING (public.can_see_claim(employee_id));
CREATE POLICY claims_insert ON public.t_expense_claims FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('expense', 'create')) AND status = 'draft'
              AND (employee_id = (SELECT auth.uid()) OR (SELECT public.has_permission('expense', 'update'))));
CREATE POLICY claims_update ON public.t_expense_claims FOR UPDATE TO authenticated USING (public.can_edit_claim(id))
  WITH CHECK (status = 'draft' AND (employee_id = (SELECT auth.uid()) OR (SELECT public.has_permission('expense', 'update'))));
CREATE POLICY claims_delete ON public.t_expense_claims FOR DELETE TO authenticated USING (public.can_edit_claim(id));
CREATE POLICY claim_lines_select ON public.t_expense_claim_lines FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_expense_claims e WHERE e.id = claim_id));
CREATE POLICY claim_lines_write ON public.t_expense_claim_lines FOR ALL TO authenticated
  USING (public.can_edit_claim(claim_id)) WITH CHECK (public.can_edit_claim(claim_id));

CREATE POLICY statements_select ON public.t_bank_statements FOR SELECT TO authenticated USING ((SELECT public.has_permission('reconcile', 'read')));
CREATE POLICY statements_insert ON public.t_bank_statements FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('reconcile', 'create')) AND status = 'open');
CREATE POLICY statements_update ON public.t_bank_statements FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('reconcile', 'update')) AND status = 'open') WITH CHECK (status = 'open');
CREATE POLICY statements_delete ON public.t_bank_statements FOR DELETE TO authenticated
  USING ((SELECT public.has_permission('reconcile', 'delete')) AND status = 'open'
         AND NOT EXISTS (SELECT 1 FROM public.t_bank_statement_lines l WHERE l.statement_id = t_bank_statements.id AND l.journal_line_id IS NOT NULL));
CREATE FUNCTION public.can_edit_statement(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT has_permission('reconcile', 'create') AND EXISTS (SELECT 1 FROM t_bank_statements WHERE id = p_id AND status = 'open');
$$;
CREATE POLICY statement_lines_select ON public.t_bank_statement_lines FOR SELECT TO authenticated
  USING ((SELECT public.has_permission('reconcile', 'read')));
CREATE POLICY statement_lines_write ON public.t_bank_statement_lines FOR ALL TO authenticated
  USING (public.can_edit_statement(statement_id) AND journal_line_id IS NULL) WITH CHECK (public.can_edit_statement(statement_id));

REVOKE INSERT, UPDATE ON public.t_cash_txns, public.t_cash_txn_lines, public.t_bank_transfers, public.t_expense_claims,
  public.t_expense_claim_lines, public.t_bank_statements, public.t_bank_statement_lines FROM authenticated;
GRANT INSERT (direction, bank_account_id, txn_date, partner_id, payee, fx_rate, reference, description),
      UPDATE (bank_account_id, txn_date, partner_id, payee, fx_rate, reference, description) ON public.t_cash_txns TO authenticated;
GRANT INSERT (txn_id, account_id, description, amount, tax_id, cost_center_id, project_id),
      UPDATE (account_id, description, amount, tax_id, cost_center_id, project_id) ON public.t_cash_txn_lines TO authenticated;
GRANT INSERT (transfer_date, from_bank_id, to_bank_id, from_amount, to_amount, from_rate, to_rate, fee_amount, reference, note),
      UPDATE (transfer_date, from_bank_id, to_bank_id, from_amount, to_amount, from_rate, to_rate, fee_amount, reference, note)
  ON public.t_bank_transfers TO authenticated;
GRANT INSERT (employee_id, claim_date, title), UPDATE (claim_date, title) ON public.t_expense_claims TO authenticated;
GRANT INSERT (claim_id, expense_date, account_id, description, amount, cost_center_id, project_id, receipt_path),
      UPDATE (expense_date, account_id, description, amount, cost_center_id, project_id, receipt_path) ON public.t_expense_claim_lines TO authenticated;
GRANT INSERT (bank_account_id, start_date, statement_date, opening_balance, closing_balance, note),
      UPDATE (start_date, statement_date, opening_balance, closing_balance, note) ON public.t_bank_statements TO authenticated;
GRANT INSERT (statement_id, line_date, description, reference, amount), UPDATE (line_date, description, reference, amount)
  ON public.t_bank_statement_lines TO authenticated;
