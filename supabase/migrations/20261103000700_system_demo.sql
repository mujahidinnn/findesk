
CREATE FUNCTION public.public_demo_mode() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE((SELECT demo_mode FROM m_settings WHERE id = 1), false);
$$;

CREATE FUNCTION public.superadmin_overview() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT is_superadmin() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  RETURN jsonb_build_object(
    'counts', jsonb_build_object(
      'users', (SELECT count(*) FROM profiles),
      'partners', (SELECT count(*) FROM m_partners),
      'accounts', (SELECT count(*) FROM m_accounts),
      'journals', (SELECT count(*) FROM t_journals WHERE status IN ('posted', 'reversed')),
      'invoices', (SELECT count(*) FROM t_invoices WHERE status <> 'draft'),
      'open_periods', (SELECT count(*) FROM m_periods WHERE status = 'open'),
      'demo_mode', (SELECT demo_mode FROM m_settings WHERE id = 1)
    ),
    'journals_14d', (SELECT COALESCE(jsonb_agg(jsonb_build_object('day', d.day::date, 'count', COALESCE(s.n, 0)) ORDER BY d.day), '[]')
                      FROM generate_series(company_today() - 13, company_today(), interval '1 day') d(day)
                      LEFT JOIN (SELECT posted_at::date AS day, count(*) AS n FROM t_journals WHERE posted_at IS NOT NULL GROUP BY 1) s
                        ON s.day = d.day::date),
    'last_audit', (SELECT COALESCE(jsonb_agg(jsonb_build_object('at', created_at, 'action', action, 'entity', entity_type) ORDER BY created_at DESC), '[]')
                     FROM (SELECT * FROM t_audit_log ORDER BY created_at DESC LIMIT 10) a),
    'last_errors', (SELECT COALESCE(jsonb_agg(jsonb_build_object('at', created_at, 'source', source, 'message', left(message, 200)) ORDER BY created_at DESC), '[]')
                      FROM (SELECT * FROM t_error_log ORDER BY created_at DESC LIMIT 10) e)
  );
END;
$$;

-- No uid means the SQL editor or pg_cron (anon cannot execute this).
CREATE OR REPLACE FUNCTION public.superadmin_reset_data() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND (is_banned() OR NOT is_superadmin()) THEN
    RAISE EXCEPTION 'Only a superadmin can reset the data' USING errcode = '42501';
  END IF;

  TRUNCATE t_bank_statement_lines, t_bank_statements, t_vat_settlements, t_asset_depreciation, t_assets, m_asset_categories,
           t_budget_lines, t_budgets, t_expense_claim_lines, t_expense_claims, t_bank_transfers, t_cash_txn_lines, t_cash_txns,
           t_note_applications, t_payment_allocations, t_payments, t_invoice_lines, t_invoices,
           t_recurring_journal_lines, t_recurring_journals, t_journal_lines, t_journals, m_periods, m_fiscal_years,
           m_bank_accounts, m_items, m_projects, m_partners, m_taxes, m_payment_terms, m_cost_centers, m_account_map, m_accounts,
           m_fx_rates, m_currencies, t_doc_counters, t_user_access_override, t_notifications, t_audit_log, t_error_log
    RESTART IDENTITY;

  DELETE FROM auth.users WHERE email LIKE '%@findesk.demo';
  DELETE FROM m_settings WHERE id = 1;
  INSERT INTO m_settings DEFAULT VALUES;
  PERFORM seed_default_master();
  PERFORM seed_asset_categories();

  INSERT INTO t_audit_log (actor_id, action, entity_type, entity_id) VALUES (auth.uid(), 'reset', 'settings', '1');
END;
$$;

-- Only GoTrue requests are blocked; seeds and sign-in bookkeeping still write.
CREATE FUNCTION public.guard_demo_credentials() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_user = 'supabase_auth_admin' AND OLD.email LIKE '%@findesk.demo'
     AND (NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password OR NEW.email IS DISTINCT FROM OLD.email
          OR COALESCE(NEW.email_change, '') <> COALESCE(OLD.email_change, '')) THEN
    RAISE EXCEPTION 'DEMO_ACCOUNT_LOCKED' USING errcode = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_guard_demo_credentials ON auth.users;
CREATE TRIGGER trg_guard_demo_credentials BEFORE UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.guard_demo_credentials();

CREATE FUNCTION public.demo_act(p_date date, p_user uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM set_config('findesk.today', COALESCE(p_date::text, ''), true);
  PERFORM set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true);
END;
$$;

CREATE FUNCTION public.demo_user(p_email text, p_name text, p_role text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM auth.users WHERE email = p_email;
  IF v_id IS NULL THEN
    v_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      p_email, crypt('Demo12345', gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', p_name),
      now(), now(), '', '', '', ''
    );
    INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_id, v_id::text,
            jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
            'email', NULL, now(), now());
  END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE profiles SET full_name = p_name, role_id = (SELECT id FROM m_roles WHERE role_name = p_role),
         employee_code = 'FD-' || upper(split_part(p_email, '@', 1))
   WHERE id = v_id;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.demo_invoice(p_type text, p_partner text, p_date date, p_lines jsonb, p_ref text DEFAULT NULL,
                                    p_orig bigint DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  p m_partners;
  v_id bigint;
BEGIN
  SELECT * INTO p FROM m_partners WHERE code = p_partner;
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date, term_id, currency, fx_rate, reference, original_invoice_id)
  VALUES (p_type, p.id, p_date, p.term_id, p.currency, COALESCE(fx_rate_on(p.currency, p_date), 1), p_ref, p_orig)
  RETURNING id INTO v_id;
  INSERT INTO t_invoice_lines (invoice_id, line_no, item_id, description, account_id, qty, unit_price, tax_id, wht_tax_id, cost_center_id)
  SELECT v_id, x.ord, it.id, COALESCE(x.l->>'desc', it.name), a.id, COALESCE((x.l->>'qty')::numeric, 1),
         COALESCE((x.l->>'price')::numeric, CASE WHEN p_type LIKE 'sales%' THEN it.sales_price ELSE it.purchase_price END),
         tx.id, wt.id, cc.id
    FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS x(l, ord)
    LEFT JOIN m_items it ON it.code = x.l->>'item'
    LEFT JOIN m_accounts a ON a.code = x.l->>'account'
    LEFT JOIN m_taxes tx ON tx.code = x.l->>'tax'
    LEFT JOIN m_taxes wt ON wt.code = x.l->>'wht'
    LEFT JOIN m_cost_centers cc ON cc.code = x.l->>'cc';
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.demo_post_invoice(p_id bigint, p_maker uuid, p_approver uuid) RETURNS t_invoices
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  inv t_invoices;
BEGIN
  UPDATE t_invoices SET created_by = p_maker WHERE id = p_id RETURNING * INTO inv;
  PERFORM demo_act(inv.invoice_date, p_maker);
  IF submit_invoice(p_id) = 'submitted' THEN
    PERFORM demo_act(inv.invoice_date, p_approver);
    PERFORM decide_invoice(p_id, true);
  END IF;
  SELECT * INTO inv FROM t_invoices WHERE id = p_id;
  RETURN inv;
END;
$$;

CREATE FUNCTION public.demo_pay(p_direction text, p_date date, p_bank text, p_invoices bigint[], p_maker uuid, p_approver uuid,
                                p_wht_code text DEFAULT NULL, p_partial numeric DEFAULT 1) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  b m_bank_accounts;
  v_partner bigint;
  v_total numeric;
  v_wht numeric := 0;
  v_tax m_taxes;
  v_id bigint;
BEGIN
  SELECT * INTO b FROM m_bank_accounts WHERE code = p_bank;
  SELECT min(partner_id), sum(round((total - paid_amount) * p_partial, 2)) INTO v_partner, v_total FROM t_invoices WHERE id = ANY (p_invoices);
  IF p_wht_code IS NOT NULL THEN
    SELECT * INTO v_tax FROM m_taxes WHERE code = p_wht_code;
    SELECT round(sum(subtotal) * v_tax.rate / 100 * p_partial, 2) INTO v_wht FROM t_invoices WHERE id = ANY (p_invoices);
  END IF;
  PERFORM demo_act(p_date, p_maker);
  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount, wht_tax_id, wht_amount, wht_slip_no, reference)
  VALUES (p_direction, v_partner, p_date, b.id, b.currency, COALESCE(fx_rate_on(b.currency, p_date), 1), v_total - v_wht,
          v_tax.id, v_wht, CASE WHEN v_wht > 0 THEN 'BP23-' || to_char(p_date, 'YYMMDD') || '-' || v_partner END, 'TRX' || to_char(p_date, 'MMDD'))
  RETURNING id INTO v_id;
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount)
  SELECT v_id, id, round((total - paid_amount) * p_partial, 2) FROM t_invoices WHERE id = ANY (p_invoices);
  IF submit_payment(v_id) = 'submitted' THEN
    PERFORM demo_act(p_date, p_approver);
    PERFORM decide_payment(v_id, true);
  END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.demo_cash(p_direction text, p_bank text, p_date date, p_desc text, p_lines jsonb, p_maker uuid, p_approver uuid,
                                 p_partner text DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM demo_act(p_date, p_maker);
  INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, partner_id, description)
  SELECT p_direction, b.id, p_date, (SELECT id FROM m_partners WHERE code = p_partner), p_desc FROM m_bank_accounts b WHERE b.code = p_bank
  RETURNING id INTO v_id;
  INSERT INTO t_cash_txn_lines (txn_id, account_id, description, amount, tax_id, cost_center_id)
  SELECT v_id, a.id, COALESCE(x->>'desc', p_desc), (x->>'amount')::numeric, tx.id, cc.id
    FROM jsonb_array_elements(p_lines) x JOIN m_accounts a ON a.code = x->>'account'
    LEFT JOIN m_taxes tx ON tx.code = x->>'tax' LEFT JOIN m_cost_centers cc ON cc.code = x->>'cc';
  IF submit_cash_txn(v_id) = 'submitted' THEN
    PERFORM demo_act(p_date, p_approver);
    PERFORM decide_cash_txn(v_id, true);
  END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.demo_journal(p_date date, p_memo text, p_lines jsonb, p_maker uuid, p_approver uuid, p_kind text DEFAULT 'manual',
                                    p_submit boolean DEFAULT true) RETURNS bigint
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM demo_act(p_date, p_maker);
  INSERT INTO t_journals (journal_date, kind, memo) VALUES (p_date, p_kind, p_memo) RETURNING id INTO v_id;
  INSERT INTO t_journal_lines (journal_id, line_no, account_id, debit, credit, memo, cost_center_id, currency, fc_amount)
  SELECT v_id, x.ord, a.id, COALESCE((x.l->>'debit')::numeric, 0), COALESCE((x.l->>'credit')::numeric, 0), x.l->>'memo', cc.id,
         x.l->>'currency', (x.l->>'fc')::numeric
    FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS x(l, ord) JOIN m_accounts a ON a.code = x.l->>'account'
    LEFT JOIN m_cost_centers cc ON cc.code = x.l->>'cc';
  IF p_submit THEN
    IF submit_journal(v_id) = 'submitted' AND p_approver IS NOT NULL THEN
      PERFORM demo_act(p_date, p_approver);
      PERFORM decide_journal(v_id, true);
    END IF;
  END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.demo_seed_run() RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public', 'auth'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE COALESCE((SELECT timezone FROM m_settings WHERE id = 1), 'Asia/Jakarta'))::date;
  v_start date := (date_trunc('month', v_today) - interval '10 months')::date;
  v_mgr uuid; v_acc uuid; v_staff uuid; v_emp uuid;
  v_month date; v_end date; v_k integer; v_d date;
  v_usd numeric := 16150;
  v_inv t_invoices;
  v_ids bigint[];
  v_id bigint;
  v_cust text;
  v_n integer;
  v_period bigint;
  v_vat numeric;
  r record;
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE email LIKE '%@findesk.demo') THEN
    RETURN jsonb_build_object('skipped', true);
  END IF;
  PERFORM setseed(0.42);

  v_mgr   := demo_user('manager@findesk.demo', 'Rina Kusumawati', 'Finance Manager');
  v_acc   := demo_user('accountant@findesk.demo', 'Budi Santoso', 'Accountant');
  v_staff := demo_user('staff@findesk.demo', 'Dewi Lestari', 'Finance Staff');
  PERFORM demo_user('auditor@findesk.demo', 'Agus Wibowo', 'Auditor');
  v_emp   := demo_user('employee@findesk.demo', 'Fajar Nugroho', 'Employee');

  UPDATE m_settings SET company_name = 'PT Nusantara Solusi Digital', legal_name = 'PT Nusantara Solusi Digital',
         address = 'Jl. Jend. Sudirman Kav. 52, Jakarta Selatan 12190', phone = '021-5150-8800', email = 'finance@nusantarasolusi.co.id',
         npwp = '01.234.567.8-012.000', is_pkp = true, demo_mode = true,
         invoice_footer = 'Pembayaran ke BCA 123-456-7890 a.n. PT Nusantara Solusi Digital'
   WHERE id = 1;
  UPDATE m_bank_accounts SET account_no = v.no, account_holder = 'PT Nusantara Solusi Digital'
    FROM (VALUES ('BCA', '123-456-7890'), ('MANDIRI', '102-00-9876543-2'), ('BCAUSD', '123-888-0001')) v(code, no)
   WHERE m_bank_accounts.code = v.code;
  FOR v_k IN 0 .. 11 LOOP
    PERFORM ensure_fiscal_year(extract(year FROM v_start + make_interval(months => v_k))::int);
  END LOOP;

  FOR v_k IN 0 .. 21 LOOP
    v_usd := round(v_usd + (random() - 0.45) * 160);
    v_d := (v_start + make_interval(months => v_k / 2))::date + CASE WHEN v_k % 2 = 1 THEN 14 ELSE 0 END;
    INSERT INTO m_fx_rates (currency, rate_date, rate) VALUES ('USD', v_d, v_usd), ('SGD', v_d, round(v_usd / 1.34, 2)),
      ('EUR', v_d, round(v_usd * 1.08, 2)) ON CONFLICT DO NOTHING;
  END LOOP;

  INSERT INTO m_partners (code, name, is_customer, is_vendor, npwp, city, phone, email, contact_person, term_id, currency, credit_limit) SELECT
    v.code, v.name, v.c, v.v, v.npwp, v.city, v.phone, v.email, v.cp, (SELECT id FROM m_payment_terms WHERE code = v.term), v.cur, v.lim
  FROM (VALUES
    ('C001', 'PT Sinar Retail Indonesia',      true,  false, '02.111.222.3-011.000', 'Jakarta',   '021-555-0101', 'ap@sinarretail.co.id', 'Hendra Wijaya', 'NET30', 'IDR', 400000000),
    ('C002', 'CV Maju Bersama',                true,  false, '03.222.333.4-421.000', 'Bandung',   '022-555-0202', 'admin@majubersama.id', 'Siti Rahma',   'NET14', 'IDR', 0),
    ('C003', 'PT Global Logistik Nusantara',   true,  false, '04.333.444.5-614.000', 'Surabaya',  '031-555-0303', 'finance@glnusantara.co.id', 'Andi Pratama', 'NET45', 'IDR', 0),
    ('C004', 'PT Rasa Kopi Nusantara',         true,  false, '05.444.555.6-013.000', 'Jakarta',   '021-555-0404', 'ap@rasakopi.co.id', 'Lina Marlina', 'NET30', 'IDR', 0),
    ('C005', 'Toko Berkah Elektronik',         true,  false, NULL,                   'Yogyakarta','0274-555-0505', 'berkah.elektronik@mail.id', 'Pak Darto', 'COD', 'IDR', 0),
    ('C006', 'PT Medika Sehat Sentosa',        true,  false, '06.555.666.7-503.000', 'Semarang',  '024-555-0606', 'keuangan@medikasehat.co.id', 'dr. Yusuf', 'NET30', 'IDR', 0),
    ('C007', 'Horizon Trading Pte Ltd',        true,  false, NULL,                   'Singapore', '+65-6555-0707', 'accounts@horizontrading.sg', 'Mr. Tan', 'NET30', 'USD', 0),
    ('C008', 'PT Bangun Karya Konstruksi',     true,  false, '07.666.777.8-121.000', 'Medan',     '061-555-0808', 'finance@bangunkarya.co.id', 'Rudi Hartono', 'NET60', 'IDR', 150000000),
    ('V001', 'PT Graha Perkantoran Sudirman',  false, true,  '08.777.888.9-012.000', 'Jakarta',   '021-555-1001', 'billing@grahasudirman.co.id', 'Bu Ratna', 'NET14', 'IDR', 0),
    ('V002', 'PT Data Prima Telekomunikasi',   false, true,  '09.888.999.0-012.000', 'Jakarta',   '021-555-1002', 'billing@dataprima.net.id', 'CS Billing', 'NET14', 'IDR', 0),
    ('V003', 'PT Distribusi Elektronik Jaya',  true,  true,  '10.999.000.1-045.000', 'Jakarta',   '021-555-1003', 'sales@dejaya.co.id', 'Kevin Halim', 'NET30', 'IDR', 0),
    ('V004', 'KAP Hendra & Rekan',             false, true,  '11.000.111.2-012.000', 'Jakarta',   '021-555-1004', 'partner@kaphendra.id', 'Hendra SE Ak', 'NET30', 'IDR', 0),
    ('V005', 'PT Media Iklan Kreatif',         false, true,  '12.111.222.3-012.000', 'Jakarta',   '021-555-1005', 'finance@mediaiklan.id', 'Rara', 'NET30', 'IDR', 0),
    ('V006', 'PT Utilitas Kawasan Bisnis',     false, true,  '13.222.333.4-012.000', 'Jakarta',   '021-555-1006', 'tagihan@utilitas.co.id', 'Billing', 'NET14', 'IDR', 0),
    ('V007', 'Shenzhen Smart Devices Co Ltd',  false, true,  NULL,                   'Shenzhen',  '+86-755-555-0707', 'export@szsmart.cn', 'Ms. Li', 'NET30', 'USD', 0)
  ) AS v(code, name, c, v, npwp, city, phone, email, cp, term, cur, lim);

  INSERT INTO m_items (code, name, kind, unit, sales_price, purchase_price, unit_cost, revenue_account_id, expense_account_id,
                       inventory_account_id, cogs_account_id, sales_tax_id, purchase_tax_id, wht_tax_id) SELECT
    v.code, v.name, v.kind, v.unit, v.sp, v.pp, v.uc, (SELECT id FROM m_accounts WHERE code = v.rev), (SELECT id FROM m_accounts WHERE code = v.exp),
    (SELECT id FROM m_accounts WHERE code = v.inv), (SELECT id FROM m_accounts WHERE code = v.cogs),
    (SELECT id FROM m_taxes WHERE code = 'PPN12'), (SELECT id FROM m_taxes WHERE code = 'PPN12'), (SELECT id FROM m_taxes WHERE code = v.wht)
  FROM (VALUES
    ('SRV-IMPL', 'Jasa implementasi sistem',  'service', 'paket', 25000000, 0, 0, '4200', NULL, NULL, NULL, 'PPH23'),
    ('SRV-MNT',  'Kontrak maintenance bulanan','service', 'bulan', 8500000, 0, 0, '4200', NULL, NULL, NULL, 'PPH23'),
    ('SRV-TRN',  'Pelatihan pengguna',         'service', 'sesi', 4500000, 0, 0, '4200', NULL, NULL, NULL, 'PPH23'),
    ('BRG-LAP',  'Laptop bisnis 14 inci',      'goods',   'unit', 14500000, 11200000, 11200000, '4100', NULL, '1140', '5100', NULL),
    ('BRG-POS',  'Terminal POS Android',       'goods',   'unit', 6800000, 5100000, 5100000, '4100', NULL, '1140', '5100', NULL),
    ('BRG-SCN',  'Barcode scanner nirkabel',   'goods',   'unit', 1250000, 820000, 820000, '4100', NULL, '1140', '5100', NULL),
    ('EXP-NET',  'Internet dedicated 100 Mbps','service', 'bulan', 0, 3500000, 0, NULL, '6300', NULL, NULL, NULL),
    ('EXP-ADS',  'Kampanye iklan digital',     'service', 'paket', 0, 15000000, 0, NULL, '6500', NULL, NULL, 'PPH23')
  ) AS v(code, name, kind, unit, sp, pp, uc, rev, exp, inv, cogs, wht);

  INSERT INTO m_projects (code, name, partner_id, start_date) VALUES
    ('PRJ-SRI', 'Implementasi ERP Sinar Retail', (SELECT id FROM m_partners WHERE code = 'C001'), v_start),
    ('PRJ-GLN', 'Integrasi TMS Global Logistik', (SELECT id FROM m_partners WHERE code = 'C003'), v_start + 60);

  PERFORM demo_journal(v_start, 'Saldo awal pembukuan', jsonb_build_array(
    jsonb_build_object('account', '1111', 'debit', 25000000), jsonb_build_object('account', '1112', 'debit', 5000000),
    jsonb_build_object('account', '1121', 'debit', 850000000), jsonb_build_object('account', '1122', 'debit', 150000000),
    jsonb_build_object('account', '1123', 'debit', round(20000 * fx_rate_on('USD', v_start), 2), 'currency', 'USD', 'fc', 20000),
    jsonb_build_object('account', '1140', 'debit', 120000000),
    jsonb_build_object('account', '1240', 'debit', 180000000), jsonb_build_object('account', '1241', 'credit', 67500000),
    jsonb_build_object('account', '1230', 'debit', 420000000), jsonb_build_object('account', '1231', 'credit', 157500000),
    jsonb_build_object('account', '2210', 'credit', 500000000), jsonb_build_object('account', '3100', 'credit', 1000000000),
    jsonb_build_object('account', '3200', 'credit', 25000000 + 5000000 + 850000000 + 150000000 + round(20000 * fx_rate_on('USD', v_start), 2)
                                                    + 120000000 + 180000000 - 67500000 + 420000000 - 157500000 - 500000000 - 1000000000)
  ), v_acc, v_mgr, 'opening');

  PERFORM demo_act(v_start, v_acc);
  INSERT INTO t_assets (code, name, category_id, acquisition_date, in_service_date, cost, method, useful_life_months, accumulated_opening, cost_center_id, location)
  SELECT v.code, v.name, c.id, v.d, v.d, v.cost, c.method, c.useful_life_months, v.acc, (SELECT id FROM m_cost_centers WHERE code = v.cc), v.loc
    FROM (VALUES ('FA-0001', 'Laptop & perangkat kantor (batch 2024)', 'KEL1', (v_start - interval '18 months')::date, 180000000, 67500000, 'HO', 'Lantai 12'),
                 ('FA-0002', 'Mobil operasional MPV', 'KEL2', (v_start - interval '36 months')::date, 420000000, 157500000, 'OPS', 'Basement P2'))
         AS v(code, name, cat, d, cost, acc, cc, loc)
    JOIN m_asset_categories c ON c.code = v.cat;
  PERFORM activate_asset(id) FROM t_assets;

  v_id := demo_invoice('purchase_bill', 'V001', v_start + 2, '[{"account": "1150", "desc": "Sewa kantor 12 bulan", "price": 240000000, "wht": "PPH42S", "cc": "HO"}]', 'INV/GPS/SEWA');
  v_inv := demo_post_invoice(v_id, v_staff, v_mgr);
  PERFORM demo_pay('out', v_start + 9, 'BCA', ARRAY[v_id], v_staff, v_mgr);
  PERFORM demo_act(v_start, v_acc);
  INSERT INTO t_recurring_journals (name, memo, frequency, next_run) VALUES ('Amortisasi sewa kantor', 'Beban sewa kantor bulanan', 'monthly',
    (v_start + interval '1 month - 1 day')::date) RETURNING id INTO v_id;
  INSERT INTO t_recurring_journal_lines (recurring_id, account_id, debit, credit, cost_center_id) VALUES
    (v_id, (SELECT id FROM m_accounts WHERE code = '6200'), 20000000, 0, (SELECT id FROM m_cost_centers WHERE code = 'HO')),
    (v_id, (SELECT id FROM m_accounts WHERE code = '1150'), 0, 20000000, NULL);

  PERFORM demo_act(v_start, v_acc);
  INSERT INTO t_budgets (name, fiscal_year_id, note) VALUES ('Anggaran operasional ' || extract(year FROM v_today),
    (SELECT id FROM m_fiscal_years WHERE year = extract(year FROM v_today)), 'Disusun bersama direksi') RETURNING id INTO v_id;
  INSERT INTO t_budget_lines (budget_id, account_id, period_no, amount)
  SELECT v_id, a.id, m, v.amt * CASE WHEN v.code IN ('4100', '4200') THEN 1 + m * 0.03 ELSE 1 END
    FROM (VALUES ('4100', 70000000), ('4200', 110000000), ('5100', 52000000), ('6100', 100000000), ('6200', 20000000),
                 ('6300', 9500000), ('6400', 3000000), ('6500', 15000000), ('6600', 2000000), ('6700', 8200000), ('6900', 2500000)) v(code, amt)
    JOIN m_accounts a ON a.code = v.code CROSS JOIN generate_series(1, 12) m;
  PERFORM demo_act(v_start, v_mgr);
  PERFORM approve_budget(v_id);

  FOR v_k IN 0 .. 10 LOOP
    v_month := (v_start + make_interval(months => v_k))::date;
    v_end := least((v_month + interval '1 month - 1 day')::date, v_today);

    FOR v_n IN 1 .. ceil((6 + random() * 4) * (v_end - v_month + 1) / 30.0)::int LOOP
      v_d := v_month + floor(random() * (v_end - v_month + 1))::int;
      v_cust := (ARRAY['C001', 'C002', 'C003', 'C004', 'C005', 'C006', 'C008', 'C001', 'C003'])[1 + floor(random() * 9)::int];
      v_id := demo_invoice('sales_invoice', v_cust, v_d, CASE floor(random() * 4)::int
          WHEN 0 THEN jsonb_build_array(jsonb_build_object('item', 'SRV-IMPL', 'qty', 1 + floor(random() * 2), 'tax', 'PPN12', 'cc', 'SLS',
                                                           'price', 18000000 + floor(random() * 15) * 1000000))
          WHEN 1 THEN jsonb_build_array(jsonb_build_object('item', 'SRV-MNT', 'qty', 1, 'tax', 'PPN12', 'cc', 'OPS'),
                                        jsonb_build_object('item', 'SRV-TRN', 'qty', 1 + floor(random() * 3), 'tax', 'PPN12', 'cc', 'OPS'))
          WHEN 2 THEN jsonb_build_array(jsonb_build_object('item', 'BRG-LAP', 'qty', 2 + floor(random() * 5), 'tax', 'PPN12', 'cc', 'SLS'),
                                        jsonb_build_object('item', 'BRG-SCN', 'qty', 2 + floor(random() * 6), 'tax', 'PPN12', 'cc', 'SLS'))
          ELSE jsonb_build_array(jsonb_build_object('item', 'BRG-POS', 'qty', 3 + floor(random() * 8), 'tax', 'PPN12', 'cc', 'SLS'),
                                 jsonb_build_object('item', 'SRV-TRN', 'qty', 1, 'tax', 'PPN12', 'cc', 'SLS')) END,
        'PO-' || v_cust || '-' || to_char(v_d, 'MMDD'));
      v_inv := demo_post_invoice(v_id, v_staff, v_mgr);
      v_d := v_inv.due_date + floor(random() * 10 - 4)::int + CASE WHEN v_cust = 'C008' THEN 45 ELSE 0 END;
      IF v_d < v_today - 2 THEN
        PERFORM demo_pay('in', greatest(v_d, v_inv.invoice_date), 'BCA', ARRAY[v_id], v_staff, v_mgr,
          CASE WHEN v_cust IN ('C003', 'C006') AND NOT EXISTS (SELECT 1 FROM t_invoice_lines l JOIN m_items i ON i.id = l.item_id
                                                               WHERE l.invoice_id = v_id AND i.kind = 'goods') THEN 'PPH23' END,
          CASE WHEN v_cust = 'C008' THEN 0.5 ELSE 1 END);
      END IF;
    END LOOP;

    IF v_k % 2 = 1 THEN
      v_d := v_month + 9;
      v_id := demo_invoice('sales_invoice', 'C007', v_d, jsonb_build_array(jsonb_build_object('item', 'SRV-IMPL', 'desc', 'System integration services',
        'price', 4000 + floor(random() * 5) * 1000, 'cc', 'SLS')), 'HZ-PO-' || v_k);
      v_inv := demo_post_invoice(v_id, v_staff, v_mgr);
      IF v_inv.due_date + 3 < v_today THEN
        PERFORM demo_pay('in', v_inv.due_date + 3, 'BCAUSD', ARRAY[v_id], v_staff, v_mgr);
      END IF;
    END IF;

    v_ids := ARRAY[]::bigint[];
    IF v_month + 10 <= v_today THEN
    v_id := demo_invoice('purchase_bill', 'V002', v_month + 4, '[{"item": "EXP-NET", "tax": "PPN12", "cc": "HO"}]', 'DP/' || to_char(v_month, 'YYYYMM'));
    PERFORM demo_post_invoice(v_id, v_staff, v_mgr); v_ids := v_ids || v_id;
    v_id := demo_invoice('purchase_bill', 'V006', v_month + 6, jsonb_build_array(jsonb_build_object('account', '6300', 'desc', 'Listrik & air kantor',
      'price', 4200000 + floor(random() * 18) * 100000, 'cc', 'HO')), 'UKB/' || to_char(v_month, 'YYYYMM'));
    PERFORM demo_post_invoice(v_id, v_staff, v_mgr); v_ids := v_ids || v_id;
    v_id := demo_invoice('purchase_bill', 'V003', v_month + 3, jsonb_build_array(
      jsonb_build_object('item', 'BRG-LAP', 'qty', 7 + floor(random() * 5), 'tax', 'PPN12'),
      jsonb_build_object('item', 'BRG-POS', 'qty', 9 + floor(random() * 7), 'tax', 'PPN12'),
      jsonb_build_object('item', 'BRG-SCN', 'qty', 12 + floor(random() * 10), 'tax', 'PPN12')), 'DEJ-' || to_char(v_month, 'YYMM'));
    PERFORM demo_post_invoice(v_id, v_staff, v_mgr);
    IF v_month + 33 < v_today THEN PERFORM demo_pay('out', v_month + 33, 'BCA', ARRAY[v_id], v_staff, v_mgr); END IF;
    IF v_k % 2 = 0 THEN
      v_id := demo_invoice('purchase_bill', 'V005', v_month + 8, '[{"item": "EXP-ADS", "tax": "PPN12", "wht": "PPH23", "cc": "SLS"}]', 'MIK-' || to_char(v_month, 'YYMM'));
      PERFORM demo_post_invoice(v_id, v_staff, v_mgr);
      IF v_month + 38 < v_today THEN PERFORM demo_pay('out', v_month + 38, 'BCA', ARRAY[v_id], v_staff, v_mgr); END IF;
    END IF;
    IF v_k = 2 THEN
      v_id := demo_invoice('purchase_bill', 'V004', v_month + 10, '[{"account": "6800", "desc": "Audit laporan keuangan tahun lalu", "price": 45000000, "tax": "PPN12", "wht": "PPH23", "cc": "FIN"}]', 'KAP-2026-031');
      PERFORM demo_post_invoice(v_id, v_staff, v_mgr);
      PERFORM demo_pay('out', v_month + 25, 'BCA', ARRAY[v_id], v_staff, v_mgr);
    END IF;
    IF v_k IN (3, 7) THEN
      v_id := demo_invoice('purchase_bill', 'V007', v_month + 5, '[{"item": "BRG-SCN", "qty": 150, "price": 52, "desc": "Wireless barcode scanner (import)"}]', 'SZ-' || v_k);
      v_inv := demo_post_invoice(v_id, v_staff, v_mgr);
      IF v_inv.due_date < v_today THEN PERFORM demo_pay('out', v_inv.due_date, 'BCAUSD', ARRAY[v_id], v_staff, v_mgr); END IF;
    END IF;
    IF v_k = 4 THEN
      v_id := demo_invoice('purchase_bill', 'V003', v_month + 7, '[{"account": "1240", "desc": "Server rak & perangkat jaringan", "price": 64000000, "tax": "PPN12", "cc": "OPS"}]', 'DEJ-SRV');
      PERFORM demo_post_invoice(v_id, v_staff, v_mgr);
      PERFORM demo_pay('out', v_month + 20, 'BCA', ARRAY[v_id], v_staff, v_mgr);
      PERFORM demo_act(v_month + 7, v_acc);
      INSERT INTO t_assets (code, name, category_id, acquisition_date, in_service_date, cost, method, useful_life_months, cost_center_id, source_invoice_id, location)
      SELECT 'FA-0003', 'Server rak & perangkat jaringan', c.id, v_month + 7, v_month + 7, 64000000, c.method, c.useful_life_months,
             (SELECT id FROM m_cost_centers WHERE code = 'OPS'), v_id, 'Ruang server' FROM m_asset_categories c WHERE c.code = 'KEL1';
      PERFORM activate_asset(id) FROM t_assets WHERE code = 'FA-0003';
    END IF;
    IF v_k = 5 THEN
      SELECT i.id INTO v_id FROM t_invoices i JOIN t_invoice_lines l ON l.invoice_id = i.id JOIN m_items it ON it.id = l.item_id
       WHERE i.doc_type = 'sales_invoice' AND it.code = 'BRG-LAP' AND l.qty >= 2 AND i.status IN ('posted', 'paid')
         AND i.invoice_date <= v_month + 12 ORDER BY i.status DESC, i.id DESC LIMIT 1;
      IF v_id IS NOT NULL THEN
        v_id := demo_invoice('sales_credit', (SELECT p.code FROM m_partners p JOIN t_invoices i ON i.partner_id = p.id WHERE i.id = v_id),
          v_month + 12, '[{"item": "BRG-LAP", "qty": 2, "tax": "PPN12", "desc": "Retur laptop cacat produksi", "cc": "SLS"}]', 'RETUR', v_id);
        PERFORM demo_post_invoice(v_id, v_staff, v_mgr);
      END IF;
    END IF;
    IF v_month + 17 < v_today THEN
      PERFORM demo_pay('out', v_month + 17, 'BCA', v_ids[1:1], v_staff, v_mgr);
      PERFORM demo_pay('out', v_month + 17, 'BCA', v_ids[2:2], v_staff, v_mgr);
    END IF;
    END IF;

    PERFORM demo_act(v_month, v_staff);
    INSERT INTO t_bank_transfers (transfer_date, from_bank_id, to_bank_id, from_amount, to_amount, note)
    SELECT v_month + 1, f.id, t.id, 5000000, 5000000, 'Isi ulang kas kecil' FROM m_bank_accounts f, m_bank_accounts t WHERE f.code = 'BCA' AND t.code = 'PETTY'
    RETURNING id INTO v_id;
    PERFORM post_transfer(v_id);
    IF v_month + 20 <= v_today THEN PERFORM demo_cash('out', 'PETTY', v_month + 5 + floor(random() * 15)::int, 'Pengeluaran kas kecil', jsonb_build_array(
      jsonb_build_object('account', '6900', 'amount', 800000 + floor(random() * 12) * 100000, 'desc', 'Konsumsi rapat', 'cc', 'HO'),
      jsonb_build_object('account', '6600', 'amount', 450000 + floor(random() * 10) * 50000, 'desc', 'ATK & perlengkapan', 'cc', 'HO'),
      jsonb_build_object('account', '6400', 'amount', 600000 + floor(random() * 10) * 100000, 'desc', 'Transport & parkir', 'cc', 'OPS')), v_staff, v_mgr);
    END IF;
    IF v_month + 19 <= v_today THEN
      PERFORM demo_act(v_month + 19, v_staff);
      INSERT INTO t_bank_transfers (transfer_date, from_bank_id, to_bank_id, from_amount, to_amount, note)
      SELECT v_month + 19, f.id, t.id, 95000000, 95000000, 'Dana payroll' FROM m_bank_accounts f, m_bank_accounts t WHERE f.code = 'BCA' AND t.code = 'MANDIRI'
      RETURNING id INTO v_id;
      PERFORM post_transfer(v_id);
    END IF;
    IF v_month + 24 <= v_today THEN
      PERFORM demo_journal(v_month + 24, 'Gaji karyawan ' || to_char(v_month, 'MM/YYYY') || ' (rekap WorkDesk)', jsonb_build_array(
        jsonb_build_object('account', '6100', 'debit', 100000000, 'cc', 'HO'),
        jsonb_build_object('account', '2123', 'credit', 4600000), jsonb_build_object('account', '2130', 'credit', 3400000, 'memo', 'BPJS'),
        jsonb_build_object('account', '1122', 'credit', 92000000)), v_acc, v_mgr);
      PERFORM demo_cash('out', 'BCA', v_month + 27, 'Angsuran pinjaman bank', jsonb_build_array(
        jsonb_build_object('account', '2210', 'amount', 10000000), jsonb_build_object('account', '8500', 'amount', 4100000)), v_staff, v_mgr);
    END IF;
    IF v_k > 0 AND v_month + 9 <= v_today THEN
      PERFORM demo_cash('out', 'BCA', v_month + 9, 'Setor PPh 21 & BPJS bulan lalu', jsonb_build_array(
        jsonb_build_object('account', '2123', 'amount', 4600000), jsonb_build_object('account', '2130', 'amount', 3400000)), v_staff, v_mgr);
      SELECT net_vat INTO v_vat FROM t_vat_settlements s JOIN m_periods p ON p.id = s.period_id
       WHERE p.start_date = (v_month - interval '1 month')::date AND s.status = 'posted';
      IF COALESCE(v_vat, 0) > 0 THEN
        PERFORM demo_cash('out', 'BCA', v_month + 14, 'Setor PPN masa ' || to_char(v_month - interval '1 month', 'MM/YYYY'),
          jsonb_build_array(jsonb_build_object('account', '2122', 'amount', v_vat)), v_staff, v_mgr);
      END IF;
    END IF;

    IF v_month + 12 <= v_today THEN
      PERFORM demo_act(v_month + 12, v_emp);
      INSERT INTO t_expense_claims (claim_date, title) VALUES (v_month + 12, 'Kunjungan klien ' || to_char(v_month, 'TMMonth')) RETURNING id INTO v_id;
      INSERT INTO t_expense_claim_lines (claim_id, expense_date, account_id, description, amount, cost_center_id)
      SELECT v_id, v_month + 10, a.id, x.descr, x.amt, (SELECT id FROM m_cost_centers WHERE code = 'SLS')
        FROM (VALUES ('6400', 'Taksi & tol ke kantor klien', 350000 + floor(random() * 8) * 50000),
                     ('6900', 'Makan siang dengan klien', 420000 + floor(random() * 6) * 40000)) x(code, descr, amt)
        JOIN m_accounts a ON a.code = x.code;
      PERFORM submit_expense_claim(v_id);
      PERFORM demo_act(v_month + 13, v_mgr);
      PERFORM decide_expense_claim(v_id, true);
      IF v_month + 15 <= v_today THEN
        PERFORM demo_act(v_month + 15, v_staff);
        PERFORM pay_expense_claim(v_id, (SELECT id FROM m_bank_accounts WHERE code = 'PETTY'), v_month + 15);
      END IF;
    END IF;

    IF (v_month + interval '1 month - 1 day')::date < v_today THEN
      v_end := (v_month + interval '1 month - 1 day')::date;
      SELECT id INTO v_period FROM m_periods WHERE start_date = v_month;
      PERFORM demo_cash('in', 'BCA', v_end, 'Jasa giro', '[{"account": "7100", "amount": 1250000}]', v_staff, v_mgr);
      PERFORM demo_cash('out', 'BCA', v_end, 'Biaya administrasi bank', '[{"account": "8100", "amount": 30000}]', v_staff, v_mgr);
      PERFORM demo_act(v_end, v_acc);
      PERFORM run_recurring_journals(v_end);
      PERFORM run_depreciation(v_period);
      BEGIN
        PERFORM settle_vat(v_period);
      EXCEPTION WHEN raise_exception THEN NULL; -- NOTHING_TO_SETTLE
      END;
      PERFORM demo_act(v_end, v_mgr);
      PERFORM revalue_fx(v_end);
      IF v_k < 8 THEN
        PERFORM close_period(v_period);
      END IF;
    END IF;
  END LOOP;

  FOR r IN SELECT p.start_date, p.end_date, (p.start_date = (date_trunc('month', v_today) - interval '2 months')::date) AS finish FROM m_periods p
            WHERE p.start_date IN ((date_trunc('month', v_today) - interval '2 months')::date, (date_trunc('month', v_today) - interval '1 month')::date)
            ORDER BY 1 LOOP
    PERFORM demo_act(r.end_date, v_acc);
    INSERT INTO t_bank_statements (bank_account_id, start_date, statement_date, opening_balance, closing_balance)
    SELECT b.id, r.start_date, r.end_date,
           COALESCE((SELECT sum(l.debit - l.credit) FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id
                      WHERE l.account_id = b.gl_account_id AND j.status IN ('posted', 'reversed') AND j.journal_date < r.start_date), 0), 0
      FROM m_bank_accounts b WHERE b.code = 'BCA' RETURNING id INTO v_id;
    INSERT INTO t_bank_statement_lines (statement_id, line_date, description, reference, amount)
    SELECT v_id, j.journal_date + CASE WHEN l.debit > 0 THEN 1 ELSE 0 END, upper(left(COALESCE(j.memo, ''), 40)), j.doc_no, l.debit - l.credit
      FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id JOIN m_bank_accounts b ON b.gl_account_id = l.account_id
     WHERE b.code = 'BCA' AND j.status IN ('posted', 'reversed') AND j.journal_date BETWEEN r.start_date AND r.end_date - 1
       AND l.debit - l.credit <> 0;
    INSERT INTO t_bank_statement_lines (statement_id, line_date, description, amount) VALUES (v_id, r.end_date, 'BIAYA TRANSFER RTGS', -35000);
    UPDATE t_bank_statements SET closing_balance = opening_balance + (SELECT sum(amount) FROM t_bank_statement_lines WHERE statement_id = v_id)
     WHERE id = v_id;
    PERFORM auto_match_statement(v_id);
    IF r.finish THEN
      PERFORM book_statement_line((SELECT id FROM t_bank_statement_lines WHERE statement_id = v_id AND description = 'BIAYA TRANSFER RTGS'),
                                  (SELECT id FROM m_accounts WHERE code = '8100'), 'Biaya transfer RTGS');
      PERFORM finish_statement(v_id);
    END IF;
  END LOOP;

  v_id := demo_invoice('purchase_bill', 'V005', v_today, '[{"item": "EXP-ADS", "price": 28000000, "tax": "PPN12", "wht": "PPH23", "cc": "SLS"}]', 'MIK-PROMO-AKHIR-TAHUN');
  PERFORM demo_act(v_today, v_staff);
  PERFORM submit_invoice(v_id);
  PERFORM demo_journal(v_today, 'Koreksi alokasi biaya internet ke Operasional', jsonb_build_array(
    jsonb_build_object('account', '6300', 'debit', 1750000, 'cc', 'OPS'), jsonb_build_object('account', '6300', 'credit', 1750000, 'cc', 'HO')),
    v_acc, NULL);
  PERFORM demo_act(v_today, v_emp);
  INSERT INTO t_expense_claims (claim_date, title) VALUES (v_today, 'Perjalanan dinas Surabaya') RETURNING id INTO v_id;
  INSERT INTO t_expense_claim_lines (claim_id, expense_date, account_id, description, amount, cost_center_id)
  SELECT v_id, v_today - 1, a.id, x.descr, x.amt, (SELECT id FROM m_cost_centers WHERE code = 'SLS')
    FROM (VALUES ('6400', 'Tiket pesawat PP Jakarta-Surabaya', 2350000), ('6400', 'Hotel 2 malam', 1600000), ('6900', 'Uang makan', 450000)) x(code, descr, amt)
    JOIN m_accounts a ON a.code = x.code;
  PERFORM submit_expense_claim(v_id);
  v_id := demo_invoice('sales_invoice', 'C004', v_today, '[{"item": "SRV-MNT", "tax": "PPN12", "cc": "OPS"}]', 'DRAFT-RK');

  PERFORM demo_act(NULL, NULL);
  RETURN jsonb_build_object('journals', (SELECT count(*) FROM t_journals), 'invoices', (SELECT count(*) FROM t_invoices));
END;
$$;

CREATE FUNCTION public.seed_demo_data() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_caller text := current_setting('request.jwt.claim.sub', true);
  v_claims text := current_setting('request.jwt.claims', true);
  v jsonb;
BEGIN
  IF auth.uid() IS NOT NULL AND (is_banned() OR NOT is_superadmin()) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  v := demo_seed_run();
  PERFORM set_config('request.jwt.claim.sub', COALESCE(v_caller, ''), true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims, ''), true);
  RETURN v;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.demo_act(date, uuid), public.demo_user(text, text, text),
  public.demo_invoice(text, text, date, jsonb, text, bigint), public.demo_post_invoice(bigint, uuid, uuid),
  public.demo_pay(text, date, text, bigint[], uuid, uuid, text, numeric), public.demo_cash(text, text, date, text, jsonb, uuid, uuid, text),
  public.demo_journal(date, text, jsonb, uuid, uuid, text, boolean), public.demo_seed_run(), public.guard_demo_credentials(),
  public.seed_asset_categories()
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.public_demo_mode(), public.superadmin_overview(), public.superadmin_reset_data(), public.seed_demo_data()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.superadmin_overview(), public.superadmin_reset_data(), public.seed_demo_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.public_demo_mode() TO anon, authenticated;
