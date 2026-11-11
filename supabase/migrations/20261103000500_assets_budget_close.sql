
CREATE TABLE public.m_asset_categories (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    method text NOT NULL DEFAULT 'straight_line' CHECK (method IN ('straight_line', 'declining', 'none')),
    useful_life_months integer NOT NULL DEFAULT 48 CHECK (useful_life_months BETWEEN 0 AND 600),
    asset_account_id bigint NOT NULL REFERENCES public.m_accounts,
    accum_account_id bigint REFERENCES public.m_accounts,
    expense_account_id bigint REFERENCES public.m_accounts,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (method = 'none' OR (accum_account_id IS NOT NULL AND expense_account_id IS NOT NULL AND useful_life_months > 0))
);

CREATE TABLE public.t_assets (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    category_id bigint NOT NULL REFERENCES public.m_asset_categories,
    acquisition_date date NOT NULL,
    in_service_date date NOT NULL,
    cost numeric(18,2) NOT NULL CHECK (cost > 0),
    salvage_value numeric(18,2) NOT NULL DEFAULT 0 CHECK (salvage_value >= 0),
    method text NOT NULL CHECK (method IN ('straight_line', 'declining', 'none')),
    useful_life_months integer NOT NULL CHECK (useful_life_months >= 0),
    accumulated_opening numeric(18,2) NOT NULL DEFAULT 0 CHECK (accumulated_opening >= 0),
    cost_center_id bigint REFERENCES public.m_cost_centers,
    location text,
    serial_no text,
    source_invoice_id bigint REFERENCES public.t_invoices,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'disposed')),
    disposal_date date,
    disposal_proceeds numeric(18,2),
    disposal_journal_id bigint REFERENCES public.t_journals,
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (salvage_value + accumulated_opening <= cost),
    CHECK (in_service_date >= acquisition_date),
    CHECK (method = 'none' OR useful_life_months > 0)
);

CREATE TABLE public.t_asset_depreciation (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id bigint NOT NULL REFERENCES public.t_assets,
    period_id bigint NOT NULL REFERENCES public.m_periods,
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    journal_id bigint NOT NULL REFERENCES public.t_journals,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (asset_id, period_id)
);

CREATE TABLE public.t_budgets (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    fiscal_year_id bigint NOT NULL REFERENCES public.m_fiscal_years,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved')),
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    approved_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    approved_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.t_budget_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    budget_id bigint NOT NULL REFERENCES public.t_budgets ON DELETE CASCADE,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    period_no integer NOT NULL CHECK (period_no BETWEEN 1 AND 12),
    amount numeric(18,2) NOT NULL DEFAULT 0,
    UNIQUE (budget_id, account_id, period_no)
);

CREATE TABLE public.t_vat_settlements (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    period_id bigint NOT NULL REFERENCES public.m_periods,
    output_vat numeric(18,2) NOT NULL,
    input_vat numeric(18,2) NOT NULL,
    net_vat numeric(18,2) NOT NULL,
    status text NOT NULL DEFAULT 'posted' CHECK (status IN ('posted', 'void')),
    journal_id bigint NOT NULL REFERENCES public.t_journals,
    void_journal_id bigint REFERENCES public.t_journals,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL
);
CREATE UNIQUE INDEX t_vat_settlements_period_idx ON public.t_vat_settlements (period_id) WHERE status = 'posted';

ALTER TABLE public.m_fiscal_years ADD COLUMN closing_journal_id bigint REFERENCES public.t_journals;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['m_asset_categories', 't_assets', 't_budgets'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t);
  END LOOP;
END $$;
CREATE TRIGGER trg_audit_assets AFTER UPDATE OF status, cost, useful_life_months, method ON public.t_assets
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('asset');
CREATE TRIGGER trg_audit_periods AFTER UPDATE OF status ON public.m_periods
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('period');
CREATE TRIGGER trg_audit_fiscal_years AFTER UPDATE OF status ON public.m_fiscal_years
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('fiscal_year');

-- Fiscal groups per PMK 72/2023 (Kelompok 1-2, permanent buildings); land does not depreciate.
CREATE FUNCTION public.seed_asset_categories() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
INSERT INTO m_asset_categories (code, name, method, useful_life_months, asset_account_id, accum_account_id, expense_account_id)
SELECT v.code, v.name, v.method, v.life, a.id, c.id, e.id FROM (VALUES
  ('KEL1', 'Kelompok 1 · komputer & peralatan kantor (4 th)', 'straight_line', 48, '1240', '1241', '6700'),
  ('KEL2', 'Kelompok 2 · kendaraan (8 th)',                   'straight_line', 96, '1230', '1231', '6700'),
  ('BGN',  'Bangunan permanen (20 th)',                       'straight_line', 240, '1220', '1221', '6700'),
  ('TANAH','Tanah (tidak disusutkan)',                        'none',          0,  '1210', NULL,   NULL)
) AS v(code, name, method, life, asset, accum, expense)
JOIN m_accounts a ON a.code = v.asset
LEFT JOIN m_accounts c ON c.code = v.accum
LEFT JOIN m_accounts e ON e.code = v.expense
ON CONFLICT (code) DO NOTHING;
$$;
SELECT public.seed_asset_categories();

CREATE FUNCTION public.asset_dep_amount(a t_assets, p_n integer, p_accum numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE
    WHEN a.method = 'none' OR p_n < 0 OR a.cost - a.salvage_value - p_accum <= 0 THEN 0
    WHEN p_n >= a.useful_life_months - 1 THEN a.cost - a.salvage_value - p_accum
    WHEN a.method = 'straight_line' THEN
      greatest(0, least(a.cost - a.salvage_value,
                        round((a.cost - a.salvage_value) / a.useful_life_months, 2) * (p_n + 1)) - p_accum)
    ELSE least(a.cost - a.salvage_value - p_accum, round((a.cost - p_accum) * 2 / a.useful_life_months, 2))
  END;
$$;

CREATE FUNCTION public.asset_month_index(a t_assets, p_date date) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT ((extract(year FROM p_date) - extract(year FROM a.in_service_date)) * 12
          + extract(month FROM p_date) - extract(month FROM a.in_service_date))::integer;
$$;

CREATE FUNCTION public.asset_accumulated(p_asset_id bigint) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT a.accumulated_opening + COALESCE((SELECT sum(amount) FROM t_asset_depreciation WHERE asset_id = a.id), 0)
    FROM t_assets a WHERE a.id = p_asset_id;
$$;

CREATE FUNCTION public.activate_asset(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('asset', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  UPDATE t_assets SET status = 'active' WHERE id = p_id AND status = 'draft';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
END;
$$;

CREATE FUNCTION public.run_depreciation(p_period_id bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
  a t_assets;
  v_amount numeric;
  v_count integer := 0;
  v_total numeric := 0;
  v_jid bigint;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT has_permission('asset', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO p FROM m_periods WHERE id = p_period_id;
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'PERIOD_MISSING' USING errcode = 'P0001';
  END IF;
  PERFORM posting_period(p.end_date);

  CREATE TEMP TABLE IF NOT EXISTS tmp_dep (asset_id bigint, amount numeric, expense_account_id bigint, accum_account_id bigint, cost_center_id bigint)
    ON COMMIT DROP;
  TRUNCATE tmp_dep;
  FOR a IN SELECT * FROM t_assets WHERE status = 'active' AND method <> 'none' AND in_service_date <= p.end_date
              AND NOT EXISTS (SELECT 1 FROM t_asset_depreciation d WHERE d.asset_id = t_assets.id AND d.period_id = p_period_id)
            ORDER BY id FOR UPDATE LOOP
    v_amount := asset_dep_amount(a, asset_month_index(a, p.end_date), asset_accumulated(a.id));
    IF v_amount > 0 THEN
      INSERT INTO tmp_dep SELECT a.id, v_amount, c.expense_account_id, c.accum_account_id, a.cost_center_id
        FROM m_asset_categories c WHERE c.id = a.category_id;
      v_count := v_count + 1;
      v_total := v_total + v_amount;
    END IF;
  END LOOP;
  IF v_count = 0 THEN
    RETURN jsonb_build_object('assets', 0, 'total', 0);
  END IF;

  v_jid := gl_create('depreciation', p.end_date, 'Penyusutan ' || to_char(p.start_date, 'MM/YYYY'), NULL, 'depreciation', p_period_id,
    (SELECT jsonb_agg(x) FROM (
       SELECT jsonb_build_object('account_id', expense_account_id, 'amount', sum(amount), 'cost_center_id', cost_center_id) x
         FROM tmp_dep GROUP BY expense_account_id, cost_center_id
       UNION ALL
       SELECT jsonb_build_object('account_id', accum_account_id, 'amount', -sum(amount)) FROM tmp_dep GROUP BY accum_account_id) s));
  INSERT INTO t_asset_depreciation (asset_id, period_id, amount, journal_id) SELECT asset_id, p_period_id, amount, v_jid FROM tmp_dep;
  RETURN jsonb_build_object('assets', v_count, 'total', v_total, 'journal_id', v_jid);
END;
$$;

CREATE FUNCTION public.asset_schedule(p_id bigint)
RETURNS TABLE (month date, amount numeric, accumulated numeric, book_value numeric, posted boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a t_assets;
  v_accum numeric;
  v_month date;
  v_amount numeric;
  v_posted numeric;
BEGIN
  IF NOT has_permission('asset', 'read') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO a FROM t_assets WHERE id = p_id;
  IF a.method = 'none' THEN
    RETURN;
  END IF;
  v_accum := a.accumulated_opening;
  FOR n IN 0 .. a.useful_life_months - 1 LOOP
    v_month := (date_trunc('month', a.in_service_date) + make_interval(months => n))::date;
    SELECT d.amount INTO v_posted FROM t_asset_depreciation d JOIN m_periods p ON p.id = d.period_id
     WHERE d.asset_id = p_id AND p.start_date = v_month;
    v_amount := COALESCE(v_posted, CASE WHEN a.status = 'disposed' THEN 0 ELSE asset_dep_amount(a, n, v_accum) END);
    v_accum := v_accum + v_amount;
    month := v_month; amount := v_amount; accumulated := v_accum; book_value := a.cost - v_accum; posted := v_posted IS NOT NULL;
    RETURN NEXT;
  END LOOP;
END;
$$;

CREATE FUNCTION public.dispose_asset(p_id bigint, p_date date, p_proceeds numeric DEFAULT 0, p_bank_id bigint DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a t_assets;
  c m_asset_categories;
  b m_bank_accounts;
  v_accum numeric;
  v_gain numeric;
BEGIN
  IF NOT has_permission('asset', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO a FROM t_assets WHERE id = p_id FOR UPDATE;
  IF a.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF COALESCE(p_proceeds, 0) < 0 OR (COALESCE(p_proceeds, 0) > 0 AND p_bank_id IS NULL) THEN
    RAISE EXCEPTION 'INVALID' USING errcode = 'P0001';
  END IF;
  SELECT * INTO c FROM m_asset_categories WHERE id = a.category_id;
  SELECT * INTO b FROM m_bank_accounts WHERE id = p_bank_id;
  IF b.id IS NOT NULL AND b.currency <> base_currency() THEN
    RAISE EXCEPTION 'CURRENCY_MISMATCH' USING errcode = 'P0001';
  END IF;
  v_accum := asset_accumulated(p_id);
  v_gain := COALESCE(p_proceeds, 0) - (a.cost - v_accum);
  UPDATE t_assets SET status = 'disposed', disposal_date = p_date, disposal_proceeds = COALESCE(p_proceeds, 0),
         note = COALESCE(p_note, note),
         disposal_journal_id = gl_create('asset_disposal', p_date, 'Pelepasan aset ' || a.code || ' ' || a.name, a.code, 'asset', p_id,
           jsonb_build_array(
             jsonb_build_object('account_id', c.accum_account_id, 'amount', v_accum),
             jsonb_build_object('account_id', b.gl_account_id, 'amount', COALESCE(p_proceeds, 0), 'currency', b.currency, 'fc_amount', COALESCE(p_proceeds, 0)),
             jsonb_build_object('account_id', c.asset_account_id, 'amount', -a.cost),
             jsonb_build_object('account_id', account_map(CASE WHEN v_gain > 0 THEN 'asset_gain' ELSE 'asset_loss' END), 'amount', -v_gain)))
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.approve_budget(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('budget', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  UPDATE t_budgets SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = p_id AND status = 'draft';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
END;
$$;

CREATE FUNCTION public.reopen_budget(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('budget', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  UPDATE t_budgets SET status = 'draft', approved_by = NULL, approved_at = NULL WHERE id = p_id AND status = 'approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
END;
$$;

CREATE FUNCTION public.account_net(p_account_id bigint, p_from date, p_to date, p_exclude_closing boolean DEFAULT true) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(sum(l.debit - l.credit), 0) FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
   WHERE l.account_id = p_account_id AND j.status IN ('posted', 'reversed') AND j.journal_date BETWEEN p_from AND p_to
     AND NOT (p_exclude_closing AND j.kind = 'closing');
$$;

CREATE FUNCTION public.settle_vat(p_period_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
  v_out numeric := 0;
  v_in numeric := 0;
  v_lines jsonb := '[]';
  r record;
  v_jid bigint;
  v_id bigint;
BEGIN
  IF NOT has_permission('tax', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO p FROM m_periods WHERE id = p_period_id;
  IF EXISTS (SELECT 1 FROM t_vat_settlements WHERE period_id = p_period_id AND status = 'posted') THEN
    RAISE EXCEPTION 'VAT_ALREADY_SETTLED' USING errcode = 'P0001';
  END IF;
  FOR r IN SELECT DISTINCT sales_account_id AS acc, 'out' AS side FROM m_taxes WHERE kind = 'vat'
           UNION SELECT DISTINCT purchase_account_id, 'in' FROM m_taxes WHERE kind = 'vat' LOOP
    DECLARE v_bal numeric := account_net(r.acc, '1900-01-01', p.end_date); BEGIN
      IF v_bal <> 0 THEN
        v_lines := v_lines || jsonb_build_object('account_id', r.acc, 'amount', -v_bal);
        IF r.side = 'out' THEN v_out := v_out - v_bal; ELSE v_in := v_in + v_bal; END IF;
      END IF;
    END;
  END LOOP;
  IF v_out = 0 AND v_in = 0 THEN
    RAISE EXCEPTION 'NOTHING_TO_SETTLE' USING errcode = 'P0001';
  END IF;
  v_lines := v_lines || jsonb_build_object('account_id', account_map(CASE WHEN v_out >= v_in THEN 'vat_payable' ELSE 'vat_overpaid' END),
                                           'amount', v_in - v_out);
  v_jid := gl_create('vat_settlement', p.end_date, 'Penyetoran PPN masa ' || to_char(p.start_date, 'MM/YYYY'), NULL, 'vat', p_period_id, v_lines);
  INSERT INTO t_vat_settlements (period_id, output_vat, input_vat, net_vat, journal_id)
  VALUES (p_period_id, v_out, v_in, v_out - v_in, v_jid) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.void_vat_settlement(p_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  s t_vat_settlements;
BEGIN
  IF NOT has_permission('tax', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO s FROM t_vat_settlements WHERE id = p_id FOR UPDATE;
  IF s.status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  UPDATE t_vat_settlements SET status = 'void', void_journal_id = gl_reverse(s.journal_id, NULL, NULL) WHERE id = p_id;
END;
$$;

-- Month-end FX revaluation of open foreign documents, unapplied payments and foreign bank balances.
-- ponytail: open amounts are as of now, not as of p_date; run it at month end, or add as-of allocation math if back-dated runs matter.
-- Reversed automatically the next day, so realized FX at settlement stays correct.
CREATE FUNCTION public.revalue_fx(p_date date) RETURNS jsonb
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
           doc_sign(i.doc_type) * (round((i.total - i.paid_amount) * r.rate, 2) - round((i.total - i.paid_amount) * i.fx_rate, 2)) AS delta
      FROM t_invoices i JOIN rates r ON r.code = i.currency
     WHERE i.status = 'posted' AND r.rate IS NOT NULL AND i.invoice_date <= p_date
    UNION ALL
    SELECT account_map(CASE p.direction WHEN 'in' THEN 'receivable' ELSE 'payable' END), p.partner_id,
           (CASE p.direction WHEN 'in' THEN -1 ELSE 1 END)
             * (round(u.open * r.rate, 2) - round(u.open * p.fx_rate, 2))
      FROM t_payments p JOIN rates r ON r.code = p.currency
      CROSS JOIN LATERAL (SELECT p.amount + p.wht_amount - COALESCE((
            SELECT sum(a.amount) FROM t_payment_allocations a JOIN t_invoices i ON i.id = a.invoice_id
             WHERE a.payment_id = p.id AND doc_feature(i.doc_type) = doc_feature(p.direction)), 0)
          - COALESCE((SELECT sum(a.amount) FROM t_payment_allocations a JOIN t_invoices i ON i.id = a.invoice_id
             WHERE a.payment_id = p.id AND doc_feature(i.doc_type) <> doc_feature(p.direction)), 0) AS open) u
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

CREATE FUNCTION public.period_checklist(p_period_id bigint)
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
  SELECT 'draft_docs', (
      (SELECT count(*) FROM t_journals WHERE status = 'draft' AND journal_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_invoices WHERE status = 'draft' AND invoice_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_payments WHERE status = 'draft' AND payment_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_cash_txns WHERE status = 'draft' AND txn_date BETWEEN p.start_date AND p.end_date)
    + (SELECT count(*) FROM t_bank_transfers WHERE status = 'draft' AND transfer_date BETWEEN p.start_date AND p.end_date)), false, '/journals'
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

CREATE FUNCTION public.close_period(p_period_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT has_permission('period', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO p FROM m_periods WHERE id = p_period_id FOR UPDATE;
  IF p.status <> 'open' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM m_periods WHERE start_date < p.start_date AND status = 'open') THEN
    RAISE EXCEPTION 'PERIOD_PREVIOUS_OPEN' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM period_checklist(p_period_id) WHERE blocking AND count > 0) THEN
    RAISE EXCEPTION 'PERIOD_HAS_PENDING' USING errcode = 'P0001';
  END IF;
  UPDATE m_periods SET status = 'closed', closed_at = now(), closed_by = auth.uid() WHERE id = p_period_id;
END;
$$;

CREATE FUNCTION public.reopen_period(p_period_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_periods;
BEGIN
  IF NOT has_permission('period', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO p FROM m_periods WHERE id = p_period_id FOR UPDATE;
  IF (SELECT status FROM m_fiscal_years WHERE id = p.fiscal_year_id) = 'closed' THEN
    RAISE EXCEPTION 'YEAR_CLOSED' USING errcode = 'P0001';
  END IF;
  UPDATE m_periods SET status = 'open', closed_at = NULL, closed_by = NULL WHERE id = p_period_id;
END;
$$;

CREATE FUNCTION public.close_fiscal_year(p_year_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  y m_fiscal_years;
  v_lines jsonb;
  v_jid bigint;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT has_permission('period', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO y FROM m_fiscal_years WHERE id = p_year_id FOR UPDATE;
  IF y.status <> 'open' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM m_periods WHERE fiscal_year_id = p_year_id AND status = 'open') THEN
    RAISE EXCEPTION 'PERIOD_STILL_OPEN' USING errcode = 'P0001';
  END IF;
  SELECT jsonb_agg(jsonb_build_object('account_id', x.id, 'amount', -x.bal)) INTO v_lines
    FROM (SELECT a.id, sum(l.debit - l.credit) bal FROM t_journal_lines l
            JOIN t_journals j ON j.id = l.journal_id JOIN m_accounts a ON a.id = l.account_id
           WHERE a.account_type IN ('revenue', 'expense') AND j.status IN ('posted', 'reversed')
             AND j.journal_date BETWEEN y.start_date AND y.end_date
           GROUP BY a.id HAVING sum(l.debit - l.credit) <> 0) x;
  IF v_lines IS NOT NULL THEN
    v_lines := v_lines || jsonb_build_object('account_id', account_map('retained_earnings'), 'amount',
      (SELECT -sum((e->>'amount')::numeric) FROM jsonb_array_elements(v_lines) e));
    v_jid := gl_create('closing', y.end_date, 'Jurnal penutup tahun ' || y.year, NULL, 'fiscal_year', p_year_id, v_lines, true);
  END IF;
  UPDATE m_fiscal_years SET status = 'closed', closed_at = now(), closed_by = auth.uid(), closing_journal_id = v_jid WHERE id = p_year_id;
  PERFORM ensure_fiscal_year(y.year + 1);
  RETURN v_jid;
END;
$$;

CREATE FUNCTION public.reopen_fiscal_year(p_year_id bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  y m_fiscal_years;
BEGIN
  IF NOT has_permission('period', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO y FROM m_fiscal_years WHERE id = p_year_id FOR UPDATE;
  IF y.status <> 'closed' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM m_fiscal_years WHERE year > y.year AND status = 'closed') THEN
    RAISE EXCEPTION 'LATER_YEAR_CLOSED' USING errcode = 'P0001';
  END IF;
  UPDATE m_fiscal_years SET status = 'open', closed_at = NULL, closed_by = NULL WHERE id = p_year_id;
  UPDATE m_periods SET status = 'open', closed_at = NULL, closed_by = NULL WHERE fiscal_year_id = p_year_id AND period_no = 12;
  IF y.closing_journal_id IS NOT NULL THEN
    PERFORM gl_reverse(y.closing_journal_id, y.end_date, 'Pembatalan jurnal penutup ' || y.year);
  END IF;
  UPDATE m_fiscal_years SET closing_journal_id = NULL WHERE id = p_year_id;
END;
$$;

CREATE FUNCTION public.pending_approvals()
RETURNS TABLE (kind text, id bigint, doc_no text, title text, partner text, amount numeric, currency text, base_amount numeric,
               requested_by text, requested_by_id uuid, submitted_at timestamptz)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM (
    SELECT 'journal', j.id, j.doc_no, j.memo, NULL::text, j.total, base_currency(), j.total, pr.full_name, j.created_by, j.submitted_at
      FROM t_journals j LEFT JOIN profiles pr ON pr.id = j.created_by WHERE j.status = 'submitted'
    UNION ALL
    SELECT 'invoice:' || i.doc_type, i.id, i.doc_no, i.reference, pa.name, i.total, i.currency, round(i.total * i.fx_rate, 2),
           pr.full_name, i.created_by, i.submitted_at
      FROM t_invoices i JOIN m_partners pa ON pa.id = i.partner_id LEFT JOIN profiles pr ON pr.id = i.created_by WHERE i.status = 'submitted'
    UNION ALL
    SELECT 'payment', p.id, p.doc_no, p.reference, pa.name, p.amount, p.currency, round(p.amount * p.fx_rate, 2),
           pr.full_name, p.created_by, p.submitted_at
      FROM t_payments p JOIN m_partners pa ON pa.id = p.partner_id LEFT JOIN profiles pr ON pr.id = p.created_by WHERE p.status = 'submitted'
    UNION ALL
    SELECT 'cash', c.id, c.doc_no, c.description, COALESCE(pa.name, c.payee), c.total, c.currency, round(c.total * c.fx_rate, 2),
           pr.full_name, c.created_by, c.submitted_at
      FROM t_cash_txns c LEFT JOIN m_partners pa ON pa.id = c.partner_id LEFT JOIN profiles pr ON pr.id = c.created_by WHERE c.status = 'submitted'
    UNION ALL
    SELECT 'expense', e.id, e.doc_no, e.title, pr.full_name, e.total, base_currency(), e.total, pr.full_name, e.employee_id, e.submitted_at
      FROM t_expense_claims e LEFT JOIN profiles pr ON pr.id = e.employee_id WHERE e.status = 'submitted'
  ) x WHERE has_permission('approval', 'read')
  ORDER BY 11;
$$;

CREATE FUNCTION public.decide_document(p_kind text, p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  CASE split_part(p_kind, ':', 1)
    WHEN 'journal' THEN PERFORM decide_journal(p_id, p_approve, p_reason);
    WHEN 'invoice' THEN PERFORM decide_invoice(p_id, p_approve, p_reason);
    WHEN 'payment' THEN PERFORM decide_payment(p_id, p_approve, p_reason);
    WHEN 'cash' THEN PERFORM decide_cash_txn(p_id, p_approve, p_reason);
    WHEN 'expense' THEN PERFORM decide_expense_claim(p_id, p_approve, p_reason);
    ELSE RAISE EXCEPTION 'INVALID' USING errcode = 'P0001';
  END CASE;
END;
$$;

ALTER TABLE public.m_asset_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_asset_depreciation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_budget_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_vat_settlements ENABLE ROW LEVEL SECURITY;

CREATE POLICY asset_categories_select ON public.m_asset_categories FOR SELECT TO authenticated USING ((SELECT public.has_any_access()));
CREATE POLICY asset_categories_write ON public.m_asset_categories FOR ALL TO authenticated
  USING ((SELECT public.has_permission('asset', 'update'))) WITH CHECK ((SELECT public.has_permission('asset', 'update')));
CREATE POLICY assets_select ON public.t_assets FOR SELECT TO authenticated USING ((SELECT public.has_permission('asset', 'read')));
CREATE POLICY assets_insert ON public.t_assets FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('asset', 'create')) AND status = 'draft');
CREATE POLICY assets_update ON public.t_assets FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('asset', 'update')) AND status = 'draft') WITH CHECK (status = 'draft');
CREATE POLICY assets_delete ON public.t_assets FOR DELETE TO authenticated
  USING ((SELECT public.has_permission('asset', 'delete')) AND status = 'draft');
CREATE POLICY depreciation_select ON public.t_asset_depreciation FOR SELECT TO authenticated USING ((SELECT public.has_permission('asset', 'read')));

CREATE POLICY budgets_select ON public.t_budgets FOR SELECT TO authenticated
  USING ((SELECT public.has_permission('budget', 'read')) OR (SELECT public.has_permission('reports', 'read')));
CREATE POLICY budgets_insert ON public.t_budgets FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('budget', 'create')) AND status = 'draft');
CREATE POLICY budgets_update ON public.t_budgets FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('budget', 'update')) AND status = 'draft') WITH CHECK (status = 'draft');
CREATE POLICY budgets_delete ON public.t_budgets FOR DELETE TO authenticated
  USING ((SELECT public.has_permission('budget', 'delete')) AND status = 'draft');
CREATE FUNCTION public.can_edit_budget(p_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT has_permission('budget', 'update') AND EXISTS (SELECT 1 FROM t_budgets WHERE id = p_id AND status = 'draft');
$$;
CREATE POLICY budget_lines_select ON public.t_budget_lines FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.t_budgets b WHERE b.id = budget_id));
CREATE POLICY budget_lines_write ON public.t_budget_lines FOR ALL TO authenticated
  USING (public.can_edit_budget(budget_id)) WITH CHECK (public.can_edit_budget(budget_id));

CREATE POLICY vat_settlements_select ON public.t_vat_settlements FOR SELECT TO authenticated USING ((SELECT public.has_permission('tax', 'read')));

REVOKE INSERT, UPDATE ON public.t_assets, public.t_budgets FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.t_asset_depreciation, public.t_vat_settlements FROM authenticated;
GRANT INSERT (code, name, category_id, acquisition_date, in_service_date, cost, salvage_value, method, useful_life_months,
              accumulated_opening, cost_center_id, location, serial_no, source_invoice_id, note),
      UPDATE (code, name, category_id, acquisition_date, in_service_date, cost, salvage_value, method, useful_life_months,
              accumulated_opening, cost_center_id, location, serial_no, source_invoice_id, note) ON public.t_assets TO authenticated;
GRANT INSERT (name, fiscal_year_id, cost_center_id, note), UPDATE (name, cost_center_id, note) ON public.t_budgets TO authenticated;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM authenticated;
GRANT EXECUTE ON FUNCTION
  public.is_banned(), public.is_superadmin(), public.is_admin(), public.has_permission(text, text), public.has_any_access(),
  public.my_rank(), public.outranks(uuid), public.can_grant(bigint, boolean, boolean, boolean, boolean), public.company_today(),
  public.log_client_error(text, text, jsonb), public.get_users_with_email(),
  public.base_currency(), public.fx_rate_on(text, date), public.open_fiscal_year(integer),
  public.submit_journal(bigint), public.decide_journal(bigint, boolean, text), public.reverse_journal(bigint, date, text),
  public.run_recurring_journals(date), public.can_read_ledger(), public.can_edit_journal(bigint),
  public.doc_feature(text), public.doc_sign(text), public.can_edit_invoice(bigint), public.can_edit_payment(bigint),
  public.partner_exposure(bigint), public.submit_invoice(bigint), public.decide_invoice(bigint, boolean, text),
  public.void_invoice(bigint, text, date), public.set_tax_invoice_no(bigint, text, date), public.apply_credit_note(bigint, bigint, numeric),
  public.payment_target_ok(text, text), public.submit_payment(bigint), public.decide_payment(bigint, boolean, text),
  public.allocate_payment(bigint, bigint, numeric), public.void_payment(bigint, text, date),
  public.submit_cash_txn(bigint), public.decide_cash_txn(bigint, boolean, text), public.void_cash_txn(bigint, text, date),
  public.post_transfer(bigint), public.void_transfer(bigint, text, date),
  public.submit_expense_claim(bigint), public.decide_expense_claim(bigint, boolean, text), public.pay_expense_claim(bigint, bigint, date),
  public.statement_book_entries(bigint), public.match_statement_line(bigint, bigint), public.auto_match_statement(bigint),
  public.book_statement_line(bigint, bigint, text), public.finish_statement(bigint), public.reopen_statement(bigint),
  public.can_edit_cash_txn(bigint), public.can_see_claim(uuid), public.can_edit_claim(bigint), public.can_edit_statement(bigint),
  public.activate_asset(bigint), public.run_depreciation(bigint), public.asset_schedule(bigint), public.asset_accumulated(bigint),
  public.dispose_asset(bigint, date, numeric, bigint, text), public.approve_budget(bigint), public.reopen_budget(bigint),
  public.can_edit_budget(bigint), public.settle_vat(bigint), public.void_vat_settlement(bigint), public.revalue_fx(date),
  public.period_checklist(bigint), public.close_period(bigint), public.reopen_period(bigint),
  public.close_fiscal_year(bigint), public.reopen_fiscal_year(bigint), public.pending_approvals(),
  public.decide_document(text, bigint, boolean, text)
TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_client_error(text, text, jsonb) TO anon;
