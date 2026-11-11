
CREATE FUNCTION public.seed_default_extras() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
INSERT INTO m_accounts (code, name, account_type, subtype, parent_id)
SELECT v.code, v.name, v.t, v.s, p.id FROM (VALUES
  ('1165', 'PPh 22 Dibayar Dimuka',                'asset',     'tax_prepaid',             '1160'),
  ('1166', 'PPh 25 Dibayar Dimuka',                'asset',     'tax_prepaid',             '1160'),
  ('1180', 'Cadangan Kerugian Piutang',            'asset',     'other_current_asset',     '1100'),
  ('1250', 'Mesin & Peralatan',                    'asset',     'fixed_asset',             '1200'),
  ('1251', 'Akumulasi Penyusutan Mesin',           'asset',     'accumulated_depreciation','1200'),
  ('2126', 'Hutang PPh 26',                        'liability', 'tax_payable',             '2120'),
  ('2127', 'Hutang PPh 22',                        'liability', 'tax_payable',             '2120'),
  ('2160', 'Hutang Gaji',                          'liability', 'accrued',                 '2100'),
  ('2170', 'Hutang BPJS',                          'liability', 'accrued',                 '2100'),
  ('6950', 'Beban Kerugian Piutang',               'expense',   'expense',                 '6')
) AS v(code, name, t, s, parent) JOIN m_accounts p ON p.code = v.parent
ON CONFLICT (code) DO NOTHING;

INSERT INTO m_taxes (code, name, kind, wht_type, rate, dpp_factor, sales_account_id, purchase_account_id)
SELECT v.code, v.name, v.kind, v.wht, v.rate, 1, s.id, p.id FROM (VALUES
  ('PPN0',    'PPN 0% (ekspor / dibebaskan)',          'vat', NULL,     0,   '2121', '1161'),
  ('PPN11',   'PPN 11% (dokumen s.d. 2024)',           'vat', NULL,     11,  '2121', '1161'),
  ('PPH22',   'PPh 22 impor (API) 2,5%',               'wht', 'pph22',  2.5, '1165', '2127'),
  ('PPH23D',  'PPh 23 dividen/bunga/royalti 15%',      'wht', 'pph23',  15,  '1162', '2124'),
  ('PPH26',   'PPh 26 non-residen 20%',                'wht', 'pph26',  20,  '1162', '2126'),
  ('PPH42BD', 'PPh 4(2) bunga deposito 20%',           'wht', 'pph4a2', 20,  '1164', '2125')
) AS v(code, name, kind, wht, rate, sales, purchase)
JOIN m_accounts s ON s.code = v.sales JOIN m_accounts p ON p.code = v.purchase
ON CONFLICT (code) DO NOTHING;
$$;
REVOKE EXECUTE ON FUNCTION public.seed_default_extras() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.seed_asset_categories() RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
SELECT public.seed_default_extras();
INSERT INTO m_asset_categories (code, name, method, useful_life_months, asset_account_id, accum_account_id, expense_account_id)
SELECT v.code, v.name, v.method, v.life, a.id, c.id, e.id FROM (VALUES
  ('KEL1',  'Kelompok 1 · komputer & peralatan kantor (4 th)', 'straight_line', 48,  '1240', '1241', '6700'),
  ('KEL2',  'Kelompok 2 · kendaraan (8 th)',                   'straight_line', 96,  '1230', '1231', '6700'),
  ('KEL3',  'Kelompok 3 · mesin & peralatan (16 th)',          'straight_line', 192, '1250', '1251', '6700'),
  ('KEL4',  'Kelompok 4 · mesin berat (20 th)',                'straight_line', 240, '1250', '1251', '6700'),
  ('BGNTP', 'Bangunan tidak permanen (10 th)',                 'straight_line', 120, '1220', '1221', '6700'),
  ('BGN',   'Bangunan permanen (20 th)',                       'straight_line', 240, '1220', '1221', '6700'),
  ('TANAH', 'Tanah (tidak disusutkan)',                        'none',          0,   '1210', NULL,   NULL)
) AS v(code, name, method, life, asset, accum, expense)
JOIN m_accounts a ON a.code = v.asset
LEFT JOIN m_accounts c ON c.code = v.accum
LEFT JOIN m_accounts e ON e.code = v.expense
ON CONFLICT (code) DO NOTHING;
$$;

SELECT public.seed_asset_categories();
