\set ON_ERROR_STOP on
SET client_min_messages = warning;
BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-00000000f001', 'mgr@test.local'),
  ('00000000-0000-0000-0000-00000000f002', 'acc@test.local'),
  ('00000000-0000-0000-0000-00000000f003', 'staff@test.local'),
  ('00000000-0000-0000-0000-00000000f004', 'aud@test.local'),
  ('00000000-0000-0000-0000-00000000f005', 'emp@test.local'),
  ('00000000-0000-0000-0000-00000000f006', 'emp2@test.local');
SET LOCAL "request.jwt.claims" = '{"role":"service_role"}';
UPDATE profiles SET role_id = CASE id
  WHEN '00000000-0000-0000-0000-00000000f001' THEN 2 WHEN '00000000-0000-0000-0000-00000000f002' THEN 3
  WHEN '00000000-0000-0000-0000-00000000f003' THEN 4 WHEN '00000000-0000-0000-0000-00000000f004' THEN 5 ELSE 6 END
 WHERE id::text LIKE '00000000-0000-0000-0000-00000000f00%';
SET LOCAL "request.jwt.claims" = '';
DO $$ BEGIN PERFORM ensure_fiscal_year(2031); END $$;
INSERT INTO m_partners (code, name, is_customer, is_vendor) VALUES ('T-C', 'Test Customer', true, true);
INSERT INTO m_partners (code, name, is_customer, currency) VALUES ('T-USD', 'Test USD Customer', true, 'USD');
INSERT INTO m_fx_rates (currency, rate_date, rate) VALUES ('USD', '2031-01-01', 15000), ('USD', '2031-02-01', 16000);
INSERT INTO m_items (code, name, revenue_account_id) SELECT 'T-SRV', 'Test service', id FROM m_accounts WHERE code = '4200';

DO $$ BEGIN
  ASSERT (SELECT count(*) FROM m_accounts a JOIN m_accounts p ON p.id = a.parent_id
           WHERE a.code IN ('1165','1166','1180','1250','1251','2126','2127','2160','2170','6950')) = 10, 'FAIL: seed extra accounts need a parent';
  ASSERT (SELECT count(*) FROM m_taxes WHERE code IN ('PPN0','PPN11','PPH22','PPH23D','PPH26','PPH42BD')) = 6, 'FAIL: seed extra tax codes';
  ASSERT (SELECT count(*) FROM m_asset_categories WHERE code IN ('KEL1','KEL2','KEL3','KEL4','BGNTP','BGN','TANAH')) = 7, 'FAIL: fiscal asset groups';
END $$;

CREATE FUNCTION pg_temp.act(p_user text, p_date date DEFAULT '2031-01-15') RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f00' || p_user, true),
         set_config('findesk.today', p_date::text, true);
$$;
CREATE FUNCTION pg_temp.gl_balance(p_code text, p_partner bigint DEFAULT NULL) RETURNS numeric LANGUAGE sql AS $$
  SELECT COALESCE(sum(l.debit - l.credit), 0) FROM t_journal_lines l JOIN t_journals j ON j.id = l.journal_id JOIN m_accounts a ON a.id = l.account_id
   WHERE a.code = p_code AND j.status IN ('posted', 'reversed') AND (p_partner IS NULL OR l.partner_id = p_partner);
$$;

DO $$ DECLARE v_inv bigint; i t_invoices; BEGIN
  PERFORM pg_temp.act('3');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) SELECT 'sales_invoice', id, '2031-01-10' FROM m_partners WHERE code = 'T-C' RETURNING id INTO v_inv;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price, tax_id)
  SELECT v_inv, (SELECT id FROM m_items WHERE code = 'T-SRV'), 2, 5000000, id FROM m_taxes WHERE code = 'PPN12';
  SELECT * INTO i FROM t_invoices WHERE id = v_inv;
  ASSERT i.subtotal = 10000000 AND i.tax_total = 1100000 AND i.total = 11100000, 'FAIL: invoice totals ' || i.total;
  ASSERT submit_invoice(v_inv) = 'posted', 'FAIL: a sales invoice within limits posts directly';
  ASSERT pg_temp.gl_balance('1130') = 11100000 AND pg_temp.gl_balance('2121') = -1100000 AND pg_temp.gl_balance('4200') = -10000000,
    'FAIL: invoice journal';
  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, amount, wht_tax_id, wht_amount)
  SELECT 'in', partner_id, '2031-01-20', (SELECT id FROM m_bank_accounts WHERE code = 'BCA'), 10900000,
         (SELECT id FROM m_taxes WHERE code = 'PPH23'), 200000 FROM t_invoices WHERE id = v_inv;
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount) SELECT max(id), v_inv, 11100000 FROM t_payments;
  ASSERT submit_payment((SELECT max(id) FROM t_payments)) = 'posted', 'FAIL: receipts post directly';
  ASSERT (SELECT status FROM t_invoices WHERE id = v_inv) = 'paid', 'FAIL: invoice should be paid';
  ASSERT pg_temp.gl_balance('1130') = 0 AND pg_temp.gl_balance('1162') = 200000, 'FAIL: receipt journal';
END $$;

DO $$ DECLARE v_inv bigint; v_pay bigint; v_p bigint := (SELECT id FROM m_partners WHERE code = 'T-USD'); BEGIN
  PERFORM pg_temp.act('3');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date, currency, fx_rate) VALUES ('sales_invoice', v_p, '2031-01-10', 'USD', 15000) RETURNING id INTO v_inv;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_inv, id, 1, 1000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_inv);
  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount)
  VALUES ('in', v_p, '2031-02-05', (SELECT id FROM m_bank_accounts WHERE code = 'BCAUSD'), 'USD', 16000, 1000) RETURNING id INTO v_pay;
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount) VALUES (v_pay, v_inv, 1000);
  PERFORM pg_temp.act('3', '2031-02-05');
  PERFORM submit_payment(v_pay);
  ASSERT pg_temp.gl_balance('1130', v_p) = 0, 'FAIL: USD receivable should clear, got ' || pg_temp.gl_balance('1130', v_p);
  ASSERT pg_temp.gl_balance('7200') = -1000000, 'FAIL: FX gain should be 1,000,000';
  PERFORM pg_temp.act('1', '2031-02-06');
  PERFORM void_payment(v_pay, 'salah input');
  ASSERT (SELECT status = 'posted' AND paid_amount = 0 FROM t_invoices WHERE id = v_inv), 'FAIL: void should reopen the invoice';
  ASSERT pg_temp.gl_balance('7200') = 0 AND pg_temp.gl_balance('1130', v_p) = 15000000, 'FAIL: void should reverse FX and receipt';
END $$;

DO $$ DECLARE v_bill bigint; BEGIN
  PERFORM pg_temp.act('3');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) SELECT 'purchase_bill', id, '2031-01-12' FROM m_partners WHERE code = 'T-C' RETURNING id INTO v_bill;
  INSERT INTO t_invoice_lines (invoice_id, account_id, qty, unit_price, wht_tax_id)
  SELECT v_bill, (SELECT id FROM m_accounts WHERE code = '6800'), 1, 20000000, id FROM m_taxes WHERE code = 'PPH23';
  ASSERT submit_invoice(v_bill) = 'submitted', 'FAIL: a 20M bill needs approval';
  BEGIN PERFORM decide_invoice(v_bill, true); RAISE EXCEPTION 'FAIL: staff approved';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.act('1');
  PERFORM decide_invoice(v_bill, true);
  ASSERT (SELECT status FROM t_invoices WHERE id = v_bill) = 'posted', 'FAIL: approved bill should post';
  ASSERT pg_temp.gl_balance('2124') = -400000 AND pg_temp.gl_balance('2110') = -19600000, 'FAIL: bill with PPh 23 journal';
  INSERT INTO t_journals (journal_date, memo) VALUES ('2031-01-13', 'self') RETURNING id INTO v_bill;
  INSERT INTO t_journal_lines (journal_id, account_id, debit, credit) SELECT v_bill, id, 100, 0 FROM m_accounts WHERE code = '6990';
  INSERT INTO t_journal_lines (journal_id, account_id, debit, credit) SELECT v_bill, id, 0, 100 FROM m_accounts WHERE code = '1111';
  ASSERT submit_journal(v_bill) = 'submitted', 'FAIL: journal approval is on by default';
  BEGIN PERFORM decide_journal(v_bill, true); RAISE EXCEPTION 'FAIL: self approval';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.act('2');
  PERFORM decide_journal(v_bill, true);
END $$;

DO $$ DECLARE v_j bigint; v_posted bigint; BEGIN
  PERFORM pg_temp.act('2');
  INSERT INTO t_journals (journal_date, memo) VALUES ('2031-01-14', 'unbalanced') RETURNING id INTO v_j;
  INSERT INTO t_journal_lines (journal_id, account_id, debit) SELECT v_j, id, 100 FROM m_accounts WHERE code = '6990';
  INSERT INTO t_journal_lines (journal_id, account_id, credit) SELECT v_j, id, 90 FROM m_accounts WHERE code = '1111';
  BEGIN PERFORM submit_journal(v_j); RAISE EXCEPTION 'FAIL: unbalanced journal submitted';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM = 'JOURNAL_UNBALANCED', 'FAIL: wrong error ' || SQLERRM; END;
  UPDATE t_journal_lines SET credit = 100 WHERE journal_id = v_j AND credit = 90;
  UPDATE t_journal_lines SET account_id = (SELECT id FROM m_accounts WHERE code = '1130') WHERE journal_id = v_j AND debit > 0;
  BEGIN PERFORM submit_journal(v_j); RAISE EXCEPTION 'FAIL: manual journal hit a control account';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM = 'CONTROL_ACCOUNT', 'FAIL: wrong error ' || SQLERRM; END;

  SELECT max(id) INTO v_posted FROM t_journals WHERE status = 'posted';
  BEGIN UPDATE t_journals SET memo = 'tampered' WHERE id = v_posted; RAISE EXCEPTION 'FAIL: posted journal edited';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE t_journal_lines SET debit = debit + 1 WHERE journal_id = v_posted; RAISE EXCEPTION 'FAIL: posted line edited';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM t_journals WHERE id = v_posted; RAISE EXCEPTION 'FAIL: posted journal deleted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  PERFORM pg_temp.act('1');
  BEGIN PERFORM close_period((SELECT p.id FROM m_periods p WHERE p.start_date = '2031-01-01')); RAISE EXCEPTION 'FAIL: closed with earlier months open';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM = 'PERIOD_PREVIOUS_OPEN', 'FAIL: wrong error ' || SQLERRM; END;
END $$;

DO $$ DECLARE v_j bigint; BEGIN
  PERFORM pg_temp.act('1');
  UPDATE m_periods SET status = 'closed' WHERE start_date < '2031-01-01';
  PERFORM close_period((SELECT id FROM m_periods WHERE start_date = '2031-01-01'));
  PERFORM pg_temp.act('2');
  INSERT INTO t_journals (journal_date, memo) VALUES ('2031-01-20', 'late') RETURNING id INTO v_j;
  INSERT INTO t_journal_lines (journal_id, account_id, debit) SELECT v_j, id, 50 FROM m_accounts WHERE code = '6990';
  INSERT INTO t_journal_lines (journal_id, account_id, credit) SELECT v_j, id, 50 FROM m_accounts WHERE code = '1111';
  BEGIN PERFORM submit_journal(v_j); RAISE EXCEPTION 'FAIL: posted into a closed month';
  EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM = 'PERIOD_CLOSED', 'FAIL: wrong error ' || SQLERRM; END;
  PERFORM pg_temp.act('1');
  BEGIN PERFORM reopen_period((SELECT id FROM m_periods WHERE start_date = '2031-01-01')); RAISE EXCEPTION 'FAIL: manager reopened';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE m_periods SET status = 'open' WHERE start_date = '2031-01-01';
END $$;

DO $$ DECLARE v_a bigint; BEGIN
  PERFORM pg_temp.act('2');
  INSERT INTO t_assets (code, name, category_id, acquisition_date, in_service_date, cost, method, useful_life_months)
  SELECT 'T-FA', 'Test asset', id, '2031-01-05', '2031-01-05', 48000000, method, useful_life_months FROM m_asset_categories WHERE code = 'KEL1'
  RETURNING id INTO v_a;
  PERFORM activate_asset(v_a);
  PERFORM run_depreciation((SELECT id FROM m_periods WHERE start_date = '2031-02-01'));
  ASSERT asset_accumulated(v_a) = 2000000, 'FAIL: catch-up depreciation ' || asset_accumulated(v_a);
  ASSERT (SELECT count(*) FROM asset_schedule(v_a)) = 48 AND (SELECT sum(amount) FROM asset_schedule(v_a)) = 48000000, 'FAIL: schedule';
END $$;

DO $$ DECLARE v_inv bigint; v_cn bigint; v_p bigint := (SELECT id FROM m_partners WHERE code = 'T-C'); BEGIN
  PERFORM pg_temp.act('3');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) VALUES ('sales_invoice', v_p, '2031-01-16') RETURNING id INTO v_inv;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_inv, id, 1, 3000000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_inv);
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date, original_invoice_id) VALUES ('sales_credit', v_p, '2031-01-17', v_inv) RETURNING id INTO v_cn;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_cn, id, 1, 1000000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_cn);
  ASSERT (SELECT paid_amount FROM t_invoices WHERE id = v_inv) = 1000000 AND (SELECT status FROM t_invoices WHERE id = v_cn) = 'paid',
    'FAIL: credit note should settle its invoice';
  PERFORM pg_temp.act('1');
  ASSERT (SELECT sum(open_base) FROM aging('receivable', '2031-12-31')) = pg_temp.gl_balance('1130'), 'FAIL: AR aging <> ledger';
  ASSERT (SELECT sum(open_base) FROM aging('payable', '2031-12-31')) = -pg_temp.gl_balance('2110'), 'FAIL: AP aging <> ledger';
  ASSERT (SELECT sum(debit) - sum(credit) FROM trial_balance('2031-01-01', '2031-12-31')) = 0, 'FAIL: trial balance';
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f003';
DO $$ BEGIN
  BEGIN UPDATE t_invoices SET total = 1 WHERE status = 'draft'; RAISE EXCEPTION 'FAIL: total writable';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE t_invoices SET status = 'posted' WHERE status = 'draft'; RAISE EXCEPTION 'FAIL: status writable';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM gl_create('manual', '2031-01-15', 'x', NULL, NULL, NULL, '[]'); RAISE EXCEPTION 'FAIL: gl_create callable';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f005';
INSERT INTO t_expense_claims (claim_date, title) VALUES ('2031-01-15', 'mine');
SELECT set_config('test.claim', (SELECT id::text FROM t_expense_claims WHERE title = 'mine'), true) \gset
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f006';
DO $$ DECLARE v_other bigint := current_setting('test.claim')::bigint; BEGIN
  BEGIN PERFORM submit_expense_claim(v_other); RAISE EXCEPTION 'FAIL: submitted another employee''s claim';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO t_expense_claims (employee_id, claim_date, title) VALUES ('00000000-0000-0000-0000-00000000f005', '2031-01-15', 'forged');
    RAISE EXCEPTION 'FAIL: filed a claim for someone else';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM t_expense_claims), 'FAIL: employee sees another employee''s claim';
  ASSERT NOT EXISTS (SELECT 1 FROM t_journals), 'FAIL: employee reads the ledger';
  ASSERT NOT EXISTS (SELECT 1 FROM t_invoices), 'FAIL: employee reads invoices';
  BEGIN PERFORM trial_balance('2031-01-01', '2031-12-31'); RAISE EXCEPTION 'FAIL: employee ran a report';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f004';
DO $$ BEGIN
  ASSERT EXISTS (SELECT 1 FROM t_journals), 'FAIL: auditor should read the ledger';
  BEGIN INSERT INTO t_invoices (doc_type, partner_id) SELECT 'sales_invoice', id FROM m_partners LIMIT 1; RAISE EXCEPTION 'FAIL: auditor wrote';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

DO $$ DECLARE v text; BEGIN
  SELECT string_agg(p.proname, ', ') INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE')
     AND p.proname NOT IN ('log_client_error', 'public_demo_mode');
  ASSERT v IS NULL, 'FAIL: anon can execute ' || v;
END $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.act('3');
DO $$ DECLARE v bigint; v_p bigint := (SELECT id FROM m_partners WHERE code = 'T-C'); v_item bigint := (SELECT id FROM m_items WHERE code = 'T-SRV'); BEGIN
  v := save_invoice_draft(jsonb_build_object('doc_type', 'sales_invoice', 'partner_id', v_p, 'invoice_date', '2031-01-18', 'currency', 'IDR', 'fx_rate', 1),
    jsonb_build_array(jsonb_build_object('item_id', v_item, 'qty', 1, 'unit_price', 100)));
  ASSERT (SELECT total FROM t_invoices WHERE id = v) = 100, 'FAIL: save_invoice_draft total';
  v := save_invoice_draft(jsonb_build_object('partner_id', v_p, 'invoice_date', '2031-01-19', 'currency', 'IDR', 'fx_rate', 1),
    jsonb_build_array(jsonb_build_object('item_id', v_item, 'qty', 2, 'unit_price', 100), jsonb_build_object('item_id', v_item, 'qty', 1, 'unit_price', 50)), v);
  ASSERT (SELECT total FROM t_invoices WHERE id = v) = 250 AND (SELECT count(*) FROM t_invoice_lines WHERE invoice_id = v) = 2, 'FAIL: save_invoice_draft replace';
  BEGIN
    PERFORM save_invoice_draft(jsonb_build_object('partner_id', v_p, 'invoice_date', '2031-01-19', 'currency', 'IDR', 'fx_rate', 1),
      jsonb_build_array(jsonb_build_object('item_id', v_item, 'qty', 0, 'unit_price', 1)), v);
    RAISE EXCEPTION 'FAIL: bad line accepted';
  EXCEPTION WHEN check_violation OR not_null_violation THEN NULL; END;
  ASSERT (SELECT count(*) FROM t_invoice_lines WHERE invoice_id = v) = 2, 'FAIL: failed save must keep the old lines';
  PERFORM submit_invoice(v);
  BEGIN PERFORM save_invoice_draft('{}', '[]', v); RAISE EXCEPTION 'FAIL: posted invoice overwritten';
  EXCEPTION WHEN OTHERS THEN ASSERT SQLERRM = 'INVALID_STATUS', 'FAIL: ' || SQLERRM; END;
  BEGIN PERFORM save_invoice_draft('{}', '[]', -1); RAISE EXCEPTION 'FAIL: missing invoice accepted';
  EXCEPTION WHEN OTHERS THEN ASSERT SQLERRM = 'NOT_FOUND', 'FAIL: ' || SQLERRM; END;
END $$;
SELECT pg_temp.act('4');
DO $$ BEGIN
  BEGIN PERFORM save_journal_draft('{"journal_date":"2031-01-18","kind":"manual","memo":"x"}', '[]'); RAISE EXCEPTION 'FAIL: auditor saved a draft';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

DO $$ DECLARE v_p bigint := (SELECT id FROM m_partners WHERE code = 'T-C'); v_dn bigint; v_pay bigint; v_inv bigint; v_cn bigint; v_app bigint;
  v_ar numeric := pg_temp.gl_balance('1130'); v_ap numeric := pg_temp.gl_balance('2110'); BEGIN
  PERFORM pg_temp.act('1');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) VALUES ('purchase_debit', v_p, '2031-01-20') RETURNING id INTO v_dn;
  INSERT INTO t_invoice_lines (invoice_id, description, account_id, qty, unit_price) SELECT v_dn, 'return', id, 1, 700000 FROM m_accounts WHERE code = '5100';
  PERFORM submit_invoice(v_dn);
  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, amount) VALUES ('in', v_p, '2031-01-21', (SELECT id FROM m_bank_accounts WHERE code = 'BCA'), 700000) RETURNING id INTO v_pay;
  PERFORM submit_payment(v_pay);
  ASSERT pg_temp.gl_balance('1130') = v_ar - 700000, 'FAIL: unallocated receipt sits on receivable';
  PERFORM allocate_payment(v_pay, v_dn, 700000);
  ASSERT (SELECT status FROM t_invoices WHERE id = v_dn) = 'paid', 'FAIL: refund should settle the debit note';
  ASSERT pg_temp.gl_balance('1130') = v_ar AND pg_temp.gl_balance('2110') = v_ap, 'FAIL: refund allocation should net both control accounts';
  ASSERT (SELECT sum(open_base) FROM aging('receivable', '2031-12-31')) = pg_temp.gl_balance('1130'), 'FAIL: AR aging after refund';
  ASSERT (SELECT sum(open_base) FROM aging('payable', '2031-12-31')) = -pg_temp.gl_balance('2110'), 'FAIL: AP aging after refund';
  PERFORM void_payment(v_pay, 'test');
  ASSERT (SELECT status FROM t_invoices WHERE id = v_dn) = 'posted' AND pg_temp.gl_balance('1130') = v_ar AND pg_temp.gl_balance('2110') = v_ap + 700000,
    'FAIL: voiding the receipt must also reverse the reclass';
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) VALUES ('sales_invoice', v_p, '2031-01-22') RETURNING id INTO v_inv;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_inv, id, 1, 500000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_inv);
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date) VALUES ('sales_credit', v_p, '2031-01-23') RETURNING id INTO v_cn;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_cn, id, 1, 200000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_cn);
  BEGIN PERFORM apply_credit_note(v_cn, v_inv, 200000, '2031-01-10'); RAISE EXCEPTION 'FAIL: applied before the documents existed';
  EXCEPTION WHEN OTHERS THEN ASSERT SQLERRM = 'INVALID', 'FAIL: ' || SQLERRM; END;
  v_app := apply_credit_note(v_cn, v_inv, 200000, '2031-01-25');
  ASSERT (SELECT applied_date FROM t_note_applications WHERE id = v_app) = '2031-01-25' AND (SELECT paid_amount FROM t_invoices WHERE id = v_inv) = 200000, 'FAIL: dated application';
  PERFORM unapply_credit_note(v_app);
  ASSERT (SELECT paid_amount FROM t_invoices WHERE id = v_inv) = 0 AND (SELECT status FROM t_invoices WHERE id = v_cn) = 'posted'
     AND NOT EXISTS (SELECT 1 FROM t_note_applications WHERE id = v_app), 'FAIL: unapply should reopen both documents';
  BEGIN PERFORM set_tax_invoice_no(-1, 'x', NULL); RAISE EXCEPTION 'FAIL: missing invoice accepted';
  EXCEPTION WHEN OTHERS THEN ASSERT SQLERRM = 'NOT_FOUND', 'FAIL: ' || SQLERRM; END;
  PERFORM void_invoice(v_cn, 'test');
  BEGIN PERFORM set_tax_invoice_no(v_cn, 'x', NULL); RAISE EXCEPTION 'FAIL: void invoice accepted';
  EXCEPTION WHEN OTHERS THEN ASSERT SQLERRM = 'INVALID_STATUS', 'FAIL: ' || SQLERRM; END;
END $$;

DO $$ DECLARE v bigint; v_p bigint := (SELECT id FROM m_partners WHERE code = 'T-C'); v_per bigint := (SELECT id FROM m_periods WHERE start_date = '2031-01-01');
  v_usd bigint := (SELECT gl_account_id FROM m_bank_accounts WHERE code = 'BCAUSD'); r record; v_net numeric; v_inv bigint; v_pay bigint; BEGIN
  PERFORM pg_temp.act('1', '2031-01-26');
  INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, payee, tax_invoice_no, tax_invoice_date)
  VALUES ('out', (SELECT id FROM m_bank_accounts WHERE code = 'BCA'), '2031-01-26', 'Warung', '010.000-31.00000001', '2031-01-26') RETURNING id INTO v;
  INSERT INTO t_cash_txn_lines (txn_id, account_id, amount, tax_id)
  SELECT v, (SELECT id FROM m_accounts WHERE code = '6800'), 1000000, id FROM m_taxes WHERE code = 'PPN12';
  ASSERT submit_cash_txn(v) = 'posted', 'FAIL: small cash out posts';
  ASSERT (SELECT tax_invoice_no FROM vat_report(v_per) WHERE doc_id = v AND doc_kind = 'cash_out') = '010.000-31.00000001', 'FAIL: vat_report uses the cash faktur number';

  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, amount, wht_tax_id, wht_amount, wht_base)
  SELECT 'in', v_p, '2031-01-26', (SELECT id FROM m_bank_accounts WHERE code = 'BCA'), 1000000, id, 40000, 2500000 FROM m_taxes WHERE code = 'PPH23' RETURNING id INTO v_pay;
  PERFORM submit_payment(v_pay);
  ASSERT (SELECT gross FROM wht_report('2031-01-01', '2031-12-31') WHERE doc_id = v_pay AND side = 'withheld_from_us') = 2500000, 'FAIL: wht_report uses the stored DPP';
  BEGIN UPDATE t_payments SET wht_base = 1 WHERE id = v_pay; RAISE EXCEPTION 'FAIL: base below the withheld amount';
  EXCEPTION WHEN check_violation OR raise_exception THEN ASSERT SQLERRM NOT LIKE 'FAIL%', SQLERRM; END;

  INSERT INTO t_cash_txns (direction, bank_account_id, txn_date, fx_rate) VALUES ('in', (SELECT id FROM m_bank_accounts WHERE code = 'BCAUSD'), '2031-02-02', 16000) RETURNING id INTO v;
  INSERT INTO t_cash_txn_lines (txn_id, account_id, amount) SELECT v, id, 100 FROM m_accounts WHERE code = '4200';
  PERFORM submit_cash_txn(v);
  SELECT * INTO r FROM general_ledger(v_usd, '2031-01-01', '2031-12-31') WHERE currency = 'USD' LIMIT 1;
  ASSERT r.fc_amount = 100 AND r.debit = 1600000, 'FAIL: general_ledger foreign amount ' || COALESCE(r.fc_amount::text, 'null');

  UPDATE m_bank_accounts SET is_active = false WHERE code = 'BCAUSD';
  SELECT * INTO r FROM bank_balances('2031-12-31') WHERE code = 'BCAUSD';
  ASSERT r.id IS NOT NULL AND r.fc = 100 AND r.base = 1600000 AND NOT r.is_active, 'FAIL: bank_balances ' || COALESCE(r.fc::text, 'null');
  ASSERT (SELECT count(*) FROM asset_register_summary()) > 0 AND (SELECT bool_and(accumulated = asset_accumulated(asset_id)) FROM asset_register_summary()),
    'FAIL: asset_register_summary';

  ASSERT (SELECT count(*) FROM cash_month_end('2031-02-28', 3)) = 3, 'FAIL: cash_month_end rows';
  ASSERT (SELECT balance FROM cash_month_end('2031-02-28', 3) WHERE month = '2031-01') = (SELECT sum(l.debit - l.credit) FROM t_journal_lines l
           JOIN t_journals j ON j.id = l.journal_id JOIN m_accounts a ON a.id = l.account_id
          WHERE a.subtype IN ('cash', 'bank') AND j.status IN ('posted', 'reversed') AND j.journal_date <= '2031-01-31'), 'FAIL: cash_month_end January';

  ASSERT partner_payable_exposure(v_p) = -pg_temp.gl_balance('2110', v_p), 'FAIL: partner_payable_exposure';

  PERFORM pg_temp.act('3', '2031-03-05');
  INSERT INTO t_invoices (doc_type, partner_id, invoice_date, currency, fx_rate)
  SELECT 'sales_invoice', id, '2031-02-10', 'USD', 15000 FROM m_partners WHERE code = 'T-USD' RETURNING id INTO v_inv;
  INSERT INTO t_invoice_lines (invoice_id, item_id, qty, unit_price) SELECT v_inv, id, 1, 1000 FROM m_items WHERE code = 'T-SRV';
  PERFORM submit_invoice(v_inv);
  INSERT INTO t_payments (direction, partner_id, payment_date, bank_account_id, currency, fx_rate, amount)
  SELECT 'in', partner_id, '2031-03-05', (SELECT id FROM m_bank_accounts WHERE code = 'BCAUSD'), 'USD', 16000, 1000 FROM t_invoices WHERE id = v_inv RETURNING id INTO v_pay;
  INSERT INTO t_payment_allocations (payment_id, invoice_id, amount) VALUES (v_pay, v_inv, 1000);
  PERFORM submit_payment(v_pay);
  PERFORM pg_temp.act('1', '2031-03-06');
  v_net := (revalue_fx('2031-02-28') ->> 'net')::numeric;
  ASSERT v_net = 2000000, 'FAIL: as-of revaluation net ' || COALESCE(v_net::text, 'null');
END $$;

INSERT INTO t_expense_claim_lines (claim_id, expense_date, account_id, description, amount, receipt_path)
SELECT c.id, '2031-01-15', (SELECT id FROM m_accounts WHERE code = '6800'), 'taxi', 50000, 'expense/00000000-0000-0000-0000-00000000f005/r1.png'
  FROM t_expense_claims c WHERE c.title = 'mine';
INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('attachments', 'expense/00000000-0000-0000-0000-00000000f005/r1.png', '00000000-0000-0000-0000-00000000f005'),
  ('attachments', 'invoices/a.pdf', '00000000-0000-0000-0000-00000000f003');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f006';
DO $$ BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM storage.objects WHERE name LIKE 'expense/%'), 'FAIL: another employee reads a receipt';
  ASSERT EXISTS (SELECT 1 FROM storage.objects WHERE name = 'invoices/a.pdf'), 'FAIL: staff attachments stay readable';
  DELETE FROM storage.objects WHERE name = 'invoices/a.pdf';
  ASSERT EXISTS (SELECT 1 FROM storage.objects WHERE name = 'invoices/a.pdf') AND (SELECT count(*) FROM storage.objects WHERE name = 'invoices/a.pdf') = 1, 'FAIL: non-owner deleted a file';
END $$;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f005';
DO $$ BEGIN ASSERT EXISTS (SELECT 1 FROM storage.objects WHERE name LIKE 'expense/%'), 'FAIL: owner cannot read own receipt'; END $$;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f001';
DO $$ BEGIN ASSERT EXISTS (SELECT 1 FROM storage.objects WHERE name LIKE 'expense/%'), 'FAIL: approver cannot read the receipt'; END $$;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000f003';
DO $$ BEGIN
  DELETE FROM storage.objects WHERE name = 'invoices/a.pdf';
  ASSERT NOT EXISTS (SELECT 1 FROM storage.objects WHERE name = 'invoices/a.pdf'), 'FAIL: uploader cannot delete own file';
END $$;
RESET ROLE;

ROLLBACK;
\echo finance_smoke ok
