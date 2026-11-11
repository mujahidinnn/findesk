
CREATE TABLE public.m_currencies (
    code text PRIMARY KEY CHECK (code ~ '^[A-Z]{3}$'),
    name text NOT NULL,
    symbol text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_fx_rates (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    currency text NOT NULL REFERENCES public.m_currencies ON UPDATE CASCADE,
    rate_date date NOT NULL,
    rate numeric(18,6) NOT NULL CHECK (rate > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (currency, rate_date)
);

CREATE TABLE public.m_accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE CHECK (code ~ '^[0-9A-Za-z.\-]+$'),
    name text NOT NULL,
    parent_id bigint REFERENCES public.m_accounts ON DELETE RESTRICT,
    account_type text NOT NULL CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    subtype text NOT NULL CHECK (subtype IN (
      'cash', 'bank', 'receivable', 'inventory', 'prepaid', 'tax_prepaid', 'other_current_asset',
      'fixed_asset', 'accumulated_depreciation', 'other_asset',
      'payable', 'tax_payable', 'accrued', 'other_current_liability', 'long_term_liability',
      'equity', 'retained_earnings',
      'revenue', 'other_income', 'cogs', 'expense', 'depreciation', 'other_expense', 'tax_expense')),
    is_postable boolean NOT NULL DEFAULT true,
    is_control boolean NOT NULL DEFAULT false,
    currency text REFERENCES public.m_currencies ON UPDATE CASCADE,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (parent_id IS DISTINCT FROM id)
);
CREATE INDEX m_accounts_parent_idx ON public.m_accounts (parent_id);

CREATE TABLE public.m_account_map (
    key text PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_cost_centers (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_payment_terms (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    days integer NOT NULL DEFAULT 0 CHECK (days BETWEEN 0 AND 3650),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- vat: PPN on the tax base (dpp_factor 11/12 = PMK 131/2024 "DPP nilai lain").
-- wht: PPh withheld from the line subtotal.
CREATE TABLE public.m_taxes (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('vat', 'wht')),
    wht_type text CHECK (wht_type IN ('pph21', 'pph22', 'pph23', 'pph4a2', 'pph15', 'pph26')),
    rate numeric(7,4) NOT NULL CHECK (rate BETWEEN 0 AND 100),
    dpp_factor numeric(20,10) NOT NULL DEFAULT 1 CHECK (dpp_factor > 0 AND dpp_factor <= 1),
    sales_account_id bigint NOT NULL REFERENCES public.m_accounts,
    purchase_account_id bigint NOT NULL REFERENCES public.m_accounts,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((kind = 'wht') = (wht_type IS NOT NULL))
);

CREATE TABLE public.m_partners (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    is_customer boolean NOT NULL DEFAULT true,
    is_vendor boolean NOT NULL DEFAULT false,
    npwp text CHECK (npwp IS NULL OR npwp ~ '^[0-9.\-]{15,22}$'),
    address text,
    city text,
    phone text,
    email text,
    contact_person text,
    term_id bigint REFERENCES public.m_payment_terms,
    currency text NOT NULL DEFAULT 'IDR' REFERENCES public.m_currencies ON UPDATE CASCADE,
    credit_limit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit_limit >= 0),
    bank_name text,
    bank_account_no text,
    bank_account_name text,
    note text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (is_customer OR is_vendor)
);

CREATE TABLE public.m_projects (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    partner_id bigint REFERENCES public.m_partners,
    start_date date,
    end_date date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

-- ponytail: goods carry a standard unit_cost for COGS; replace with StockDesk's moving average when the apps merge.
CREATE TABLE public.m_items (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    kind text NOT NULL DEFAULT 'service' CHECK (kind IN ('goods', 'service')),
    unit text NOT NULL DEFAULT 'pcs',
    sales_price numeric(18,2) NOT NULL DEFAULT 0 CHECK (sales_price >= 0),
    purchase_price numeric(18,2) NOT NULL DEFAULT 0 CHECK (purchase_price >= 0),
    unit_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    revenue_account_id bigint REFERENCES public.m_accounts,
    expense_account_id bigint REFERENCES public.m_accounts,
    inventory_account_id bigint REFERENCES public.m_accounts,
    cogs_account_id bigint REFERENCES public.m_accounts,
    sales_tax_id bigint REFERENCES public.m_taxes,
    purchase_tax_id bigint REFERENCES public.m_taxes,
    wht_tax_id bigint REFERENCES public.m_taxes,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((inventory_account_id IS NULL) = (cogs_account_id IS NULL))
);

CREATE TABLE public.m_bank_accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL,
    kind text NOT NULL DEFAULT 'bank' CHECK (kind IN ('bank', 'cash', 'petty')),
    bank_name text,
    account_no text,
    account_holder text,
    currency text NOT NULL DEFAULT 'IDR' REFERENCES public.m_currencies ON UPDATE CASCADE,
    gl_account_id bigint NOT NULL UNIQUE REFERENCES public.m_accounts,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_fiscal_years (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year integer NOT NULL UNIQUE CHECK (year BETWEEN 2000 AND 2100),
    start_date date NOT NULL,
    end_date date NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    closed_at timestamptz,
    closed_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_periods (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year_id bigint NOT NULL REFERENCES public.m_fiscal_years ON DELETE CASCADE,
    period_no integer NOT NULL CHECK (period_no BETWEEN 1 AND 12),
    start_date date NOT NULL UNIQUE,
    end_date date NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    closed_at timestamptz,
    closed_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    UNIQUE (fiscal_year_id, period_no),
    CHECK (end_date >= start_date)
);

CREATE TABLE public.t_doc_counters (
    kind text NOT NULL,
    period text NOT NULL,
    last_no integer NOT NULL,
    PRIMARY KEY (kind, period)
);

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['m_currencies', 'm_fx_rates', 'm_accounts', 'm_account_map', 'm_cost_centers', 'm_payment_terms',
                           'm_taxes', 'm_partners', 'm_projects', 'm_items', 'm_bank_accounts'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['m_accounts', 'm_account_map', 'm_taxes', 'm_partners', 'm_bank_accounts', 'm_currencies'] LOOP
    EXECUTE format('CREATE TRIGGER trg_audit_%1$s AFTER INSERT OR UPDATE OR DELETE ON public.%1$I FOR EACH ROW EXECUTE FUNCTION public.audit_row_change(%1$L)', t);
  END LOOP;
END $$;

CREATE FUNCTION public.guard_account_parent() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.parent_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM m_accounts p WHERE p.id = NEW.parent_id AND NOT p.is_postable AND p.account_type = NEW.account_type) THEN
    RAISE EXCEPTION 'ACCOUNT_PARENT_INVALID' USING errcode = '23514';
  END IF;
  IF NEW.is_control AND NEW.subtype NOT IN ('receivable', 'payable') THEN
    RAISE EXCEPTION 'ACCOUNT_CONTROL_INVALID' USING errcode = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_guard_account_parent BEFORE INSERT OR UPDATE ON public.m_accounts
  FOR EACH ROW EXECUTE FUNCTION public.guard_account_parent();

CREATE FUNCTION public.account_map(p_key text) RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v bigint := (SELECT account_id FROM m_account_map WHERE key = p_key);
BEGIN
  IF v IS NULL THEN
    RAISE EXCEPTION 'ACCOUNT_MAP_MISSING' USING errcode = 'P0001', detail = p_key;
  END IF;
  RETURN v;
END;
$$;

CREATE FUNCTION public.base_currency() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT base_currency FROM m_settings WHERE id = 1;
$$;

CREATE FUNCTION public.fx_rate_on(p_currency text, p_date date) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT CASE WHEN p_currency = base_currency() THEN 1::numeric ELSE
    (SELECT rate FROM m_fx_rates WHERE currency = p_currency AND rate_date <= p_date ORDER BY rate_date DESC LIMIT 1) END;
$$;

-- Gapless per kind and month: the counter row stays locked until the posting transaction commits.
CREATE FUNCTION public.next_doc_no(p_kind text, p_date date) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_prefix text := (SELECT doc_prefixes->>p_kind FROM m_settings WHERE id = 1);
  v_period text := to_char(p_date, 'YYYY/MM');
  v_no     integer;
BEGIN
  IF v_prefix IS NULL THEN
    RAISE EXCEPTION 'No document prefix for %', p_kind;
  END IF;
  INSERT INTO t_doc_counters (kind, period, last_no) VALUES (p_kind, v_period, 1)
  ON CONFLICT (kind, period) DO UPDATE SET last_no = t_doc_counters.last_no + 1
  RETURNING last_no INTO v_no;
  RETURN v_prefix || '/' || v_period || '/' || lpad(v_no::text, 4, '0');
END;
$$;

CREATE FUNCTION public.ensure_fiscal_year(p_year integer) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint;
BEGIN
  SELECT id INTO v_id FROM m_fiscal_years WHERE year = p_year;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;
  INSERT INTO m_fiscal_years (year, start_date, end_date)
  VALUES (p_year, make_date(p_year, 1, 1), make_date(p_year, 12, 31)) RETURNING id INTO v_id;
  INSERT INTO m_periods (fiscal_year_id, period_no, start_date, end_date)
  SELECT v_id, m, make_date(p_year, m, 1), (make_date(p_year, m, 1) + interval '1 month - 1 day')::date
    FROM generate_series(1, 12) m;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.open_fiscal_year(p_year integer) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('period', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM m_fiscal_years WHERE year = p_year) THEN
    RAISE EXCEPTION 'FISCAL_YEAR_EXISTS';
  END IF;
  RETURN ensure_fiscal_year(p_year);
END;
$$;

CREATE FUNCTION public.seed_default_master() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO m_currencies (code, name, symbol) VALUES
    ('IDR', 'Rupiah Indonesia', 'Rp'), ('USD', 'US Dollar', '$'), ('SGD', 'Singapore Dollar', 'S$'),
    ('EUR', 'Euro', '€'), ('CNY', 'Chinese Yuan', '¥')
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO m_accounts (code, name, account_type, subtype, is_postable, is_control, currency, parent_id)
  SELECT v.code, v.name, v.t, v.s, v.p, v.c, v.cur, NULL
    FROM (VALUES
    ('1',    'Aset',                              'asset', 'other_current_asset', false, false, NULL),
    ('1100', 'Aset Lancar',                       'asset', 'other_current_asset', false, false, NULL),
    ('1110', 'Kas',                               'asset', 'cash', false, false, NULL),
    ('1111', 'Kas Besar',                         'asset', 'cash', true, false, NULL),
    ('1112', 'Kas Kecil',                         'asset', 'cash', true, false, NULL),
    ('1120', 'Bank',                              'asset', 'bank', false, false, NULL),
    ('1121', 'Bank BCA',                          'asset', 'bank', true, false, NULL),
    ('1122', 'Bank Mandiri',                      'asset', 'bank', true, false, NULL),
    ('1123', 'Bank BCA USD',                      'asset', 'bank', true, false, 'USD'),
    ('1130', 'Piutang Usaha',                     'asset', 'receivable', true, true, NULL),
    ('1140', 'Persediaan Barang Dagang',          'asset', 'inventory', true, false, NULL),
    ('1150', 'Biaya Dibayar Dimuka',              'asset', 'prepaid', true, false, NULL),
    ('1160', 'Pajak Dibayar Dimuka',              'asset', 'tax_prepaid', false, false, NULL),
    ('1161', 'PPN Masukan',                       'asset', 'tax_prepaid', true, false, NULL),
    ('1162', 'PPh 23 Dibayar Dimuka',             'asset', 'tax_prepaid', true, false, NULL),
    ('1163', 'PPN Lebih Bayar',                   'asset', 'tax_prepaid', true, false, NULL),
    ('1164', 'PPh 4(2) Dibayar Dimuka',           'asset', 'tax_prepaid', true, false, NULL),
    ('1170', 'Piutang Karyawan',                  'asset', 'other_current_asset', true, false, NULL),
    ('1200', 'Aset Tidak Lancar',                 'asset', 'fixed_asset', false, false, NULL),
    ('1210', 'Tanah',                             'asset', 'fixed_asset', true, false, NULL),
    ('1220', 'Bangunan',                          'asset', 'fixed_asset', true, false, NULL),
    ('1221', 'Akumulasi Penyusutan Bangunan',     'asset', 'accumulated_depreciation', true, false, NULL),
    ('1230', 'Kendaraan',                         'asset', 'fixed_asset', true, false, NULL),
    ('1231', 'Akumulasi Penyusutan Kendaraan',    'asset', 'accumulated_depreciation', true, false, NULL),
    ('1240', 'Peralatan Kantor',                  'asset', 'fixed_asset', true, false, NULL),
    ('1241', 'Akumulasi Penyusutan Peralatan',    'asset', 'accumulated_depreciation', true, false, NULL),
    ('2',    'Liabilitas',                        'liability', 'other_current_liability', false, false, NULL),
    ('2100', 'Liabilitas Jangka Pendek',          'liability', 'other_current_liability', false, false, NULL),
    ('2110', 'Hutang Usaha',                      'liability', 'payable', true, true, NULL),
    ('2120', 'Hutang Pajak',                      'liability', 'tax_payable', false, false, NULL),
    ('2121', 'PPN Keluaran',                      'liability', 'tax_payable', true, false, NULL),
    ('2122', 'Hutang PPN',                        'liability', 'tax_payable', true, false, NULL),
    ('2123', 'Hutang PPh 21',                     'liability', 'tax_payable', true, false, NULL),
    ('2124', 'Hutang PPh 23',                     'liability', 'tax_payable', true, false, NULL),
    ('2125', 'Hutang PPh 4(2)',                   'liability', 'tax_payable', true, false, NULL),
    ('2130', 'Biaya Masih Harus Dibayar',         'liability', 'accrued', true, false, NULL),
    ('2140', 'Hutang Reimburse Karyawan',         'liability', 'other_current_liability', true, false, NULL),
    ('2150', 'Pendapatan Diterima Dimuka',        'liability', 'other_current_liability', true, false, NULL),
    ('2200', 'Liabilitas Jangka Panjang',         'liability', 'long_term_liability', false, false, NULL),
    ('2210', 'Hutang Bank Jangka Panjang',        'liability', 'long_term_liability', true, false, NULL),
    ('3',    'Ekuitas',                           'equity', 'equity', false, false, NULL),
    ('3100', 'Modal Disetor',                     'equity', 'equity', true, false, NULL),
    ('3200', 'Laba Ditahan',                      'equity', 'retained_earnings', true, false, NULL),
    ('3300', 'Ekuitas Saldo Awal',                'equity', 'equity', true, false, NULL),
    ('3400', 'Dividen / Prive',                   'equity', 'equity', true, false, NULL),
    ('4',    'Pendapatan',                        'revenue', 'revenue', false, false, NULL),
    ('4100', 'Penjualan Barang',                  'revenue', 'revenue', true, false, NULL),
    ('4200', 'Pendapatan Jasa',                   'revenue', 'revenue', true, false, NULL),
    ('4300', 'Retur & Potongan Penjualan',        'revenue', 'revenue', true, false, NULL),
    ('5',    'Harga Pokok Penjualan',             'expense', 'cogs', false, false, NULL),
    ('5100', 'Harga Pokok Penjualan',             'expense', 'cogs', true, false, NULL),
    ('6',    'Beban Operasional',                 'expense', 'expense', false, false, NULL),
    ('6100', 'Beban Gaji & Tunjangan',            'expense', 'expense', true, false, NULL),
    ('6200', 'Beban Sewa',                        'expense', 'expense', true, false, NULL),
    ('6300', 'Beban Listrik, Air & Internet',     'expense', 'expense', true, false, NULL),
    ('6400', 'Beban Transportasi & Perjalanan',   'expense', 'expense', true, false, NULL),
    ('6500', 'Beban Pemasaran & Iklan',           'expense', 'expense', true, false, NULL),
    ('6600', 'Beban Perlengkapan Kantor',         'expense', 'expense', true, false, NULL),
    ('6700', 'Beban Penyusutan',                  'expense', 'depreciation', true, false, NULL),
    ('6800', 'Beban Jasa Profesional',            'expense', 'expense', true, false, NULL),
    ('6900', 'Beban Konsumsi & Rapat',            'expense', 'expense', true, false, NULL),
    ('6990', 'Beban Lain-lain',                   'expense', 'expense', true, false, NULL),
    ('7',    'Pendapatan & Beban Lain',           'revenue', 'other_income', false, false, NULL),
    ('7100', 'Pendapatan Bunga',                  'revenue', 'other_income', true, false, NULL),
    ('7200', 'Laba Selisih Kurs',                 'revenue', 'other_income', true, false, NULL),
    ('7300', 'Laba Pelepasan Aset',               'revenue', 'other_income', true, false, NULL),
    ('8',    'Beban Lain-lain',                   'expense', 'other_expense', false, false, NULL),
    ('8100', 'Beban Administrasi Bank',           'expense', 'other_expense', true, false, NULL),
    ('8200', 'Rugi Selisih Kurs',                 'expense', 'other_expense', true, false, NULL),
    ('8300', 'Rugi Pelepasan Aset',               'expense', 'other_expense', true, false, NULL),
    ('8400', 'Selisih Pembulatan',                'expense', 'other_expense', true, false, NULL),
    ('8500', 'Beban Bunga Pinjaman',              'expense', 'other_expense', true, false, NULL),
    ('9',    'Beban Pajak Penghasilan',           'expense', 'tax_expense', false, false, NULL),
    ('9100', 'Beban Pajak Penghasilan Badan',     'expense', 'tax_expense', true, false, NULL)
    ) AS v(code, name, t, s, p, c, cur)
  ON CONFLICT (code) DO NOTHING;

  UPDATE m_accounts a SET parent_id = (
    SELECT p.id FROM m_accounts p
     WHERE p.code <> a.code AND a.code LIKE rtrim(p.code, '0') || '%' AND NOT p.is_postable AND p.account_type = a.account_type
     ORDER BY length(rtrim(p.code, '0')) DESC LIMIT 1)
   WHERE a.parent_id IS NULL AND length(a.code) > 1;

  INSERT INTO m_account_map (key, account_id)
  SELECT v.key, a.id FROM (VALUES
    ('receivable', '1130'), ('payable', '2110'), ('vat_payable', '2122'), ('vat_overpaid', '1163'),
    ('employee_payable', '2140'), ('retained_earnings', '3200'), ('opening_equity', '3300'),
    ('fx_gain', '7200'), ('fx_loss', '8200'), ('rounding', '8400'), ('bank_fee', '8100'),
    ('asset_gain', '7300'), ('asset_loss', '8300'), ('sales_revenue', '4100'), ('purchase_expense', '6990')
  ) AS v(key, code) JOIN m_accounts a ON a.code = v.code
  ON CONFLICT (key) DO NOTHING;

  INSERT INTO m_taxes (code, name, kind, wht_type, rate, dpp_factor, sales_account_id, purchase_account_id)
  SELECT v.code, v.name, v.kind, v.wht, v.rate, v.dpp, s.id, p.id
    FROM (VALUES
    ('PPN12',   'PPN 12% (DPP 11/12)',            'vat', NULL,     12,  11.0 / 12, '2121', '1161'),
    ('PPN12M',  'PPN 12% barang mewah',            'vat', NULL,     12,  1,         '2121', '1161'),
    ('PPH23',   'PPh 23 jasa 2%',                  'wht', 'pph23',  2,   1,         '1162', '2124'),
    ('PPH42S',  'PPh 4(2) sewa tanah/bangunan 10%','wht', 'pph4a2', 10,  1,         '1164', '2125'),
    ('PPH21BP', 'PPh 21 bukan pegawai 2,5%',       'wht', 'pph21',  2.5, 1,         '1162', '2123')
    ) AS v(code, name, kind, wht, rate, dpp, sales, purchase)
    JOIN m_accounts s ON s.code = v.sales JOIN m_accounts p ON p.code = v.purchase
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO m_payment_terms (code, name, days) VALUES
    ('COD', 'Tunai', 0), ('NET14', '14 hari', 14), ('NET30', '30 hari', 30), ('NET45', '45 hari', 45), ('NET60', '60 hari', 60)
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO m_cost_centers (code, name) VALUES
    ('HO', 'Kantor Pusat'), ('SLS', 'Penjualan'), ('OPS', 'Operasional'), ('FIN', 'Keuangan & Umum')
  ON CONFLICT (code) DO NOTHING;

  INSERT INTO m_bank_accounts (code, name, kind, bank_name, currency, gl_account_id)
  SELECT v.code, v.name, v.kind, v.bank, v.cur, a.id FROM (VALUES
    ('KAS',     'Kas Besar',     'cash',  NULL,           'IDR', '1111'),
    ('PETTY',   'Kas Kecil',     'petty', NULL,           'IDR', '1112'),
    ('BCA',     'BCA Operasional','bank', 'BCA',          'IDR', '1121'),
    ('MANDIRI', 'Mandiri Payroll','bank', 'Bank Mandiri', 'IDR', '1122'),
    ('BCAUSD',  'BCA USD',       'bank',  'BCA',          'USD', '1123')
  ) AS v(code, name, kind, bank, cur, acc) JOIN m_accounts a ON a.code = v.acc
  ON CONFLICT (code) DO NOTHING;

  PERFORM ensure_fiscal_year(extract(year FROM company_today())::int);
END;
$$;

SELECT public.seed_default_master();

DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('m_currencies', 'settings'), ('m_accounts', 'account'), ('m_account_map', 'settings'), ('m_cost_centers', 'account'),
    ('m_payment_terms', 'settings'), ('m_taxes', 'tax'), ('m_partners', 'partner'), ('m_projects', 'account'),
    ('m_items', 'partner'), ('m_bank_accounts', 'cash-bank'), ('m_fx_rates', 'cash-bank')
  ) AS v(t, f) LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.t);
    EXECUTE format('CREATE POLICY %1$s_select ON public.%1$I FOR SELECT TO authenticated USING ((SELECT public.has_any_access()))', r.t);
    EXECUTE format('CREATE POLICY %1$s_insert ON public.%1$I FOR INSERT TO authenticated WITH CHECK ((SELECT public.has_permission(%2$L, ''create'')))', r.t, r.f);
    EXECUTE format('CREATE POLICY %1$s_update ON public.%1$I FOR UPDATE TO authenticated USING ((SELECT public.has_permission(%2$L, ''update''))) WITH CHECK ((SELECT public.has_permission(%2$L, ''update'')))', r.t, r.f);
    EXECUTE format('CREATE POLICY %1$s_delete ON public.%1$I FOR DELETE TO authenticated USING ((SELECT public.has_permission(%2$L, ''delete'')))', r.t, r.f);
  END LOOP;
END $$;

ALTER TABLE public.m_fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_doc_counters ENABLE ROW LEVEL SECURITY;
CREATE POLICY fiscal_years_select ON public.m_fiscal_years FOR SELECT TO authenticated USING ((SELECT public.has_any_access()));
CREATE POLICY periods_select ON public.m_periods FOR SELECT TO authenticated USING ((SELECT public.has_any_access()));
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.m_fiscal_years, public.m_periods FROM authenticated;
REVOKE ALL ON public.t_doc_counters FROM authenticated;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.next_doc_no(text, date), public.ensure_fiscal_year(integer), public.seed_default_master(),
  public.account_map(text), public.guard_account_parent() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.base_currency(), public.fx_rate_on(text, date), public.open_fiscal_year(integer) TO authenticated;
