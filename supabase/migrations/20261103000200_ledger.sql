-- General ledger: every posting in the app lands here through gl_post_journal (directly or via gl_create).
-- A posted journal is never edited or deleted; it is corrected by a reversal.

CREATE TABLE public.t_journals (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_no text UNIQUE,
    journal_date date NOT NULL DEFAULT public.company_today(),
    period_id bigint REFERENCES public.m_periods,
    kind text NOT NULL DEFAULT 'manual' CHECK (kind IN (
      'manual', 'opening', 'recurring', 'reversal', 'sales_invoice', 'sales_credit', 'purchase_bill', 'purchase_debit',
      'payment_in', 'payment_out', 'cash_in', 'cash_out', 'transfer', 'expense', 'expense_payment', 'depreciation',
      'asset_disposal', 'vat_settlement', 'fx_realized', 'fx_reval', 'closing')),
    source_type text,
    source_id bigint,
    memo text,
    reference text,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'posted', 'reversed')),
    total numeric(18,2) NOT NULL DEFAULT 0,
    reversal_of bigint REFERENCES public.t_journals,
    reversed_by bigint REFERENCES public.t_journals,
    reject_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    submitted_at timestamptz,
    approved_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    posted_at timestamptz,
    posted_by uuid REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_journals_date_idx ON public.t_journals (journal_date, status);
CREATE INDEX t_journals_source_idx ON public.t_journals (source_type, source_id);
CREATE INDEX t_journals_period_idx ON public.t_journals (period_id);

CREATE TABLE public.t_journal_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    journal_id bigint NOT NULL REFERENCES public.t_journals ON DELETE CASCADE,
    line_no integer NOT NULL DEFAULT 0,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    debit numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    memo text,
    partner_id bigint REFERENCES public.m_partners,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects,
    currency text REFERENCES public.m_currencies ON UPDATE CASCADE,
    fc_amount numeric(18,2),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (NOT (debit > 0 AND credit > 0))
);
CREATE INDEX t_journal_lines_journal_idx ON public.t_journal_lines (journal_id);
CREATE INDEX t_journal_lines_account_idx ON public.t_journal_lines (account_id, journal_id);
CREATE INDEX t_journal_lines_partner_idx ON public.t_journal_lines (partner_id) WHERE partner_id IS NOT NULL;

CREATE TRIGGER trg_journals_updated_at BEFORE UPDATE ON public.t_journals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_audit_journals AFTER UPDATE OF status ON public.t_journals
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.audit_row_change('journal');

-- Posted rows only ever move posted -> reversed (with reversed_by). Holds for SECURITY DEFINER code too.
CREATE FUNCTION public.guard_journal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'JOURNAL_LOCKED' USING errcode = '42501';
    END IF;
    RETURN OLD;
  END IF;
  IF OLD.status IN ('posted', 'reversed') AND NOT (
       OLD.status = 'posted' AND NEW.status = 'reversed' AND NEW.reversed_by IS NOT NULL
       AND to_jsonb(NEW) - ARRAY['status', 'reversed_by', 'updated_at'] = to_jsonb(OLD) - ARRAY['status', 'reversed_by', 'updated_at']) THEN
    RAISE EXCEPTION 'JOURNAL_LOCKED' USING errcode = '42501';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_guard_journal BEFORE UPDATE OR DELETE ON public.t_journals
  FOR EACH ROW EXECUTE FUNCTION public.guard_journal();

CREATE FUNCTION public.guard_journal_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_status text := (SELECT status FROM t_journals WHERE id = COALESCE(NEW.journal_id, OLD.journal_id));
BEGIN
  IF v_status IS NOT NULL AND v_status <> 'draft' THEN
    RAISE EXCEPTION 'JOURNAL_LOCKED' USING errcode = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;
CREATE TRIGGER trg_guard_journal_line BEFORE INSERT OR UPDATE OR DELETE ON public.t_journal_lines
  FOR EACH ROW EXECUTE FUNCTION public.guard_journal_line();

CREATE FUNCTION public.guard_account_entries() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF (NEW.account_type IS DISTINCT FROM OLD.account_type OR NEW.subtype IS DISTINCT FROM OLD.subtype
      OR (OLD.is_postable AND NOT NEW.is_postable) OR NEW.currency IS DISTINCT FROM OLD.currency)
     AND EXISTS (SELECT 1 FROM t_journal_lines WHERE account_id = OLD.id) THEN
    RAISE EXCEPTION 'ACCOUNT_HAS_ENTRIES' USING errcode = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_guard_account_entries BEFORE UPDATE ON public.m_accounts
  FOR EACH ROW EXECUTE FUNCTION public.guard_account_entries();

CREATE FUNCTION public.user_can(p_user uuid, p_feature_key text, p_action text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
  SELECT NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user AND banned_until > now()) AND COALESCE(
    (SELECT CASE p_action
       WHEN 'create' THEN o.can_create WHEN 'read' THEN o.can_read
       WHEN 'update' THEN o.can_update WHEN 'delete' THEN o.can_delete END
       FROM t_user_access_override o JOIN m_features f ON f.id = o.feature_id
      WHERE o.user_id = p_user AND f.feature_key = p_feature_key AND o.is_override_active),
    (SELECT CASE p_action
       WHEN 'create' THEN rp.can_create WHEN 'read' THEN rp.can_read
       WHEN 'update' THEN rp.can_update WHEN 'delete' THEN rp.can_delete END
       FROM t_role_permissions rp JOIN m_features f ON f.id = rp.feature_id JOIN profiles p ON p.role_id = rp.role_id
      WHERE p.id = p_user AND f.feature_key = p_feature_key),
    false);
$$;

CREATE FUNCTION public.notify_users(p_feature text, p_action text, p_title text, p_body text, p_link text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  INSERT INTO t_notifications (user_id, title, body, link)
  SELECT p.id, p_title, p_body, p_link FROM profiles p
   WHERE p.id IS DISTINCT FROM auth.uid() AND user_can(p.id, p_feature, p_action);
$$;

CREATE FUNCTION public.notify_user(p_user uuid, p_title text, p_body text, p_link text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  INSERT INTO t_notifications (user_id, title, body, link)
  SELECT p_user, p_title, p_body, p_link WHERE p_user IS NOT NULL AND p_user IS DISTINCT FROM auth.uid();
$$;

-- The open period holding a date. p_allow_closed is only for year-end closing entries.
CREATE FUNCTION public.posting_period(p_date date, p_allow_closed boolean DEFAULT false) RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint;
  v_status text;
  v_year_status text;
BEGIN
  SELECT p.id, p.status, y.status INTO v_id, v_status, v_year_status
    FROM m_periods p JOIN m_fiscal_years y ON y.id = p.fiscal_year_id
   WHERE p_date BETWEEN p.start_date AND p.end_date;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'PERIOD_MISSING' USING errcode = 'P0001';
  END IF;
  IF NOT p_allow_closed AND (v_status = 'closed' OR v_year_status = 'closed') THEN
    RAISE EXCEPTION 'PERIOD_CLOSED' USING errcode = 'P0001';
  END IF;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.journal_check(p_id bigint, p_manual boolean) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_debit numeric;
  v_credit numeric;
  v_count integer;
BEGIN
  SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0), count(*) FILTER (WHERE debit > 0 OR credit > 0)
    INTO v_debit, v_credit, v_count FROM t_journal_lines WHERE journal_id = p_id;
  IF v_count < 2 OR v_debit = 0 THEN
    RAISE EXCEPTION 'JOURNAL_EMPTY' USING errcode = 'P0001';
  END IF;
  IF v_debit <> v_credit THEN
    RAISE EXCEPTION 'JOURNAL_UNBALANCED' USING errcode = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM t_journal_lines l JOIN m_accounts a ON a.id = l.account_id
              WHERE l.journal_id = p_id AND (NOT a.is_postable OR NOT a.is_active)) THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_POSTABLE' USING errcode = 'P0001';
  END IF;
  IF p_manual AND EXISTS (SELECT 1 FROM t_journal_lines l JOIN m_accounts a ON a.id = l.account_id
                           WHERE l.journal_id = p_id AND a.is_control) THEN
    RAISE EXCEPTION 'CONTROL_ACCOUNT' USING errcode = 'P0001';
  END IF;
  RETURN v_debit;
END;
$$;

CREATE FUNCTION public.gl_post_journal(p_id bigint, p_allow_closed boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  j t_journals;
  v_total numeric;
BEGIN
  SELECT * INTO j FROM t_journals WHERE id = p_id FOR UPDATE;
  IF j.status NOT IN ('draft', 'submitted') THEN
    RAISE EXCEPTION 'JOURNAL_LOCKED' USING errcode = '42501';
  END IF;
  v_total := journal_check(p_id, j.kind IN ('manual', 'opening', 'recurring'));
  UPDATE t_journals
     SET status = 'posted', total = v_total, period_id = posting_period(j.journal_date, p_allow_closed),
         doc_no = COALESCE(doc_no, next_doc_no(CASE WHEN kind = 'closing' THEN 'closing' ELSE 'journal' END, j.journal_date)),
         posted_at = now(), posted_by = auth.uid()
   WHERE id = p_id;
END;
$$;

CREATE FUNCTION public.gl_create(p_kind text, p_date date, p_memo text, p_reference text, p_source_type text,
                                 p_source_id bigint, p_lines jsonb, p_allow_closed boolean DEFAULT false) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id bigint;
  v_diff numeric;
BEGIN
  INSERT INTO t_journals (kind, journal_date, memo, reference, source_type, source_id)
  VALUES (p_kind, p_date, p_memo, p_reference, p_source_type, p_source_id) RETURNING id INTO v_id;

  INSERT INTO t_journal_lines (journal_id, line_no, account_id, debit, credit, memo, partner_id, cost_center_id, project_id, currency, fc_amount)
  SELECT v_id, row_number() OVER (), x.account_id,
         round(CASE WHEN x.amount IS NOT NULL THEN greatest(x.amount, 0) ELSE COALESCE(x.debit, 0) END, 2),
         round(CASE WHEN x.amount IS NOT NULL THEN greatest(-x.amount, 0) ELSE COALESCE(x.credit, 0) END, 2),
         x.memo, x.partner_id, x.cost_center_id, x.project_id, x.currency, x.fc_amount
    FROM jsonb_to_recordset(p_lines) AS x(account_id bigint, amount numeric, debit numeric, credit numeric, memo text,
                                          partner_id bigint, cost_center_id bigint, project_id bigint, currency text, fc_amount numeric)
   WHERE round(COALESCE(x.amount, COALESCE(x.debit, 0) - COALESCE(x.credit, 0)), 2) <> 0 OR COALESCE(x.fc_amount, 0) <> 0;

  SELECT COALESCE(sum(debit - credit), 0) INTO v_diff FROM t_journal_lines WHERE journal_id = v_id;
  IF v_diff <> 0 AND abs(v_diff) <= 1 THEN
    INSERT INTO t_journal_lines (journal_id, line_no, account_id, debit, credit, memo)
    VALUES (v_id, 999, account_map('rounding'), greatest(-v_diff, 0), greatest(v_diff, 0), 'Pembulatan');
  END IF;

  PERFORM gl_post_journal(v_id, p_allow_closed);
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.gl_reverse(p_id bigint, p_date date, p_memo text) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  j t_journals;
  v_date date;
  v_new bigint;
BEGIN
  SELECT * INTO j FROM t_journals WHERE id = p_id FOR UPDATE;
  IF j.status <> 'posted' THEN
    RAISE EXCEPTION 'JOURNAL_NOT_POSTED' USING errcode = 'P0001';
  END IF;
  v_date := COALESCE(p_date, CASE WHEN EXISTS (
      SELECT 1 FROM m_periods p JOIN m_fiscal_years y ON y.id = p.fiscal_year_id
       WHERE j.journal_date BETWEEN p.start_date AND p.end_date AND p.status = 'open' AND y.status = 'open')
    THEN j.journal_date ELSE greatest(company_today(), j.journal_date) END);
  IF v_date < j.journal_date THEN
    RAISE EXCEPTION 'REVERSAL_BEFORE_ORIGINAL' USING errcode = 'P0001';
  END IF;

  INSERT INTO t_journals (kind, journal_date, memo, reference, source_type, source_id, reversal_of)
  VALUES ('reversal', v_date, COALESCE(p_memo, 'Pembalik ' || j.doc_no), j.doc_no, j.source_type, j.source_id, j.id)
  RETURNING id INTO v_new;
  INSERT INTO t_journal_lines (journal_id, line_no, account_id, debit, credit, memo, partner_id, cost_center_id, project_id, currency, fc_amount)
  SELECT v_new, line_no, account_id, credit, debit, memo, partner_id, cost_center_id, project_id, currency, -fc_amount
    FROM t_journal_lines WHERE journal_id = p_id;
  PERFORM gl_post_journal(v_new);
  UPDATE t_journals SET status = 'reversed', reversed_by = v_new WHERE id = p_id;
  RETURN v_new;
END;
$$;

CREATE FUNCTION public.submit_journal(p_id bigint) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  j t_journals;
BEGIN
  SELECT * INTO j FROM t_journals WHERE id = p_id FOR UPDATE;
  IF j.id IS NULL OR j.kind NOT IN ('manual', 'opening') THEN
    RAISE EXCEPTION 'NOT_FOUND' USING errcode = 'P0001';
  END IF;
  IF NOT (has_permission('journal', 'update') OR (j.created_by = auth.uid() AND has_permission('journal', 'create'))) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF j.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  PERFORM journal_check(p_id, true);
  PERFORM posting_period(j.journal_date);
  IF NOT (SELECT require_journal_approval FROM m_settings WHERE id = 1) THEN
    PERFORM gl_post_journal(p_id);
    RETURN 'posted';
  END IF;
  UPDATE t_journals SET status = 'submitted', submitted_at = now(), reject_reason = NULL WHERE id = p_id;
  PERFORM notify_users('approval', 'update', 'Jurnal menunggu persetujuan', j.memo, '/approvals');
  RETURN 'submitted';
END;
$$;

CREATE FUNCTION public.decide_journal(p_id bigint, p_approve boolean, p_reason text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  j t_journals;
BEGIN
  IF NOT has_permission('approval', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  SELECT * INTO j FROM t_journals WHERE id = p_id FOR UPDATE;
  IF j.status IS DISTINCT FROM 'submitted' THEN
    RAISE EXCEPTION 'INVALID_STATUS' USING errcode = 'P0001';
  END IF;
  IF j.created_by = auth.uid() THEN
    RAISE EXCEPTION 'SELF_APPROVAL' USING errcode = '42501';
  END IF;
  IF p_approve THEN
    UPDATE t_journals SET approved_by = auth.uid() WHERE id = p_id;
    PERFORM gl_post_journal(p_id);
    PERFORM notify_user(j.created_by, 'Jurnal disetujui', j.memo, '/journals?id=' || p_id);
  ELSE
    IF COALESCE(trim(p_reason), '') = '' THEN
      RAISE EXCEPTION 'REASON_REQUIRED' USING errcode = 'P0001';
    END IF;
    UPDATE t_journals SET status = 'draft', reject_reason = p_reason WHERE id = p_id;
    PERFORM notify_user(j.created_by, 'Jurnal ditolak', p_reason, '/journals?id=' || p_id);
  END IF;
END;
$$;

CREATE FUNCTION public.reverse_journal(p_id bigint, p_date date DEFAULT NULL, p_reason text DEFAULT NULL) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT has_permission('journal', 'delete') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM t_journals WHERE id = p_id AND kind IN ('manual', 'opening', 'recurring')) THEN
    RAISE EXCEPTION 'JOURNAL_FROM_SUBLEDGER' USING errcode = 'P0001';
  END IF;
  RETURN gl_reverse(p_id, p_date, p_reason);
END;
$$;

CREATE TABLE public.t_recurring_journals (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    memo text,
    frequency text NOT NULL DEFAULT 'monthly' CHECK (frequency IN ('monthly', 'quarterly', 'yearly')),
    next_run date NOT NULL,
    end_date date,
    is_active boolean NOT NULL DEFAULT true,
    last_journal_id bigint REFERENCES public.t_journals,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.t_recurring_journal_lines (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recurring_id bigint NOT NULL REFERENCES public.t_recurring_journals ON DELETE CASCADE,
    account_id bigint NOT NULL REFERENCES public.m_accounts,
    debit numeric(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit numeric(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    memo text,
    cost_center_id bigint REFERENCES public.m_cost_centers,
    project_id bigint REFERENCES public.m_projects,
    CHECK (NOT (debit > 0 AND credit > 0))
);
CREATE INDEX t_recurring_journal_lines_idx ON public.t_recurring_journal_lines (recurring_id);
CREATE TRIGGER trg_recurring_updated_at BEFORE UPDATE ON public.t_recurring_journals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ponytail: no cron; the closing checklist flags due templates and someone presses run. Add pg_cron if that is forgotten.
CREATE FUNCTION public.run_recurring_journals(p_as_of date DEFAULT NULL) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_as_of date := COALESCE(p_as_of, company_today());
  r t_recurring_journals;
  v_count integer := 0;
  v_jid bigint;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT has_permission('journal', 'update') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;
  FOR r IN SELECT * FROM t_recurring_journals
            WHERE is_active AND next_run <= v_as_of AND (end_date IS NULL OR next_run <= end_date)
            ORDER BY next_run FOR UPDATE LOOP
    WHILE r.next_run <= v_as_of AND (r.end_date IS NULL OR r.next_run <= r.end_date) LOOP
      v_jid := gl_create('recurring', r.next_run, COALESCE(r.memo, r.name), r.name, 'recurring', r.id,
        (SELECT jsonb_agg(jsonb_build_object('account_id', account_id, 'debit', debit, 'credit', credit, 'memo', memo,
                                             'cost_center_id', cost_center_id, 'project_id', project_id))
           FROM t_recurring_journal_lines WHERE recurring_id = r.id));
      r.next_run := (r.next_run + CASE r.frequency WHEN 'monthly' THEN interval '1 month'
                                                   WHEN 'quarterly' THEN interval '3 months' ELSE interval '1 year' END)::date;
      UPDATE t_recurring_journals SET next_run = r.next_run, last_journal_id = v_jid WHERE id = r.id;
      v_count := v_count + 1;
    END LOOP;
  END LOOP;
  RETURN v_count;
END;
$$;

ALTER TABLE public.t_journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_recurring_journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_recurring_journal_lines ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.can_read_ledger() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT has_permission('journal', 'read') OR has_permission('reports', 'read');
$$;

CREATE POLICY journals_select ON public.t_journals FOR SELECT TO authenticated USING ((SELECT public.can_read_ledger()));
CREATE POLICY journals_insert ON public.t_journals FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.has_permission('journal', 'create')) AND status = 'draft' AND kind IN ('manual', 'opening')
              AND created_by = (SELECT auth.uid()));
CREATE POLICY journals_update ON public.t_journals FOR UPDATE TO authenticated
  USING (status = 'draft' AND kind IN ('manual', 'opening')
         AND ((SELECT public.has_permission('journal', 'update')) OR created_by = (SELECT auth.uid())))
  WITH CHECK (status = 'draft' AND kind IN ('manual', 'opening'));
CREATE POLICY journals_delete ON public.t_journals FOR DELETE TO authenticated
  USING (status = 'draft' AND kind IN ('manual', 'opening')
         AND ((SELECT public.has_permission('journal', 'delete')) OR created_by = (SELECT auth.uid())));

CREATE FUNCTION public.can_edit_journal(p_journal_id bigint) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM t_journals j WHERE j.id = p_journal_id AND j.status = 'draft' AND j.kind IN ('manual', 'opening')
                  AND (has_permission('journal', 'update') OR (j.created_by = auth.uid() AND has_permission('journal', 'create'))));
$$;

CREATE POLICY journal_lines_select ON public.t_journal_lines FOR SELECT TO authenticated USING ((SELECT public.can_read_ledger()));
CREATE POLICY journal_lines_write ON public.t_journal_lines FOR ALL TO authenticated
  USING (public.can_edit_journal(journal_id)) WITH CHECK (public.can_edit_journal(journal_id));

CREATE POLICY recurring_select ON public.t_recurring_journals FOR SELECT TO authenticated USING ((SELECT public.has_permission('journal', 'read')));
CREATE POLICY recurring_insert ON public.t_recurring_journals FOR INSERT TO authenticated WITH CHECK ((SELECT public.has_permission('journal', 'update')));
CREATE POLICY recurring_update ON public.t_recurring_journals FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('journal', 'update'))) WITH CHECK ((SELECT public.has_permission('journal', 'update')));
CREATE POLICY recurring_delete ON public.t_recurring_journals FOR DELETE TO authenticated USING ((SELECT public.has_permission('journal', 'delete')));
CREATE POLICY recurring_lines_select ON public.t_recurring_journal_lines FOR SELECT TO authenticated USING ((SELECT public.has_permission('journal', 'read')));
CREATE POLICY recurring_lines_write ON public.t_recurring_journal_lines FOR ALL TO authenticated
  USING ((SELECT public.has_permission('journal', 'update'))) WITH CHECK ((SELECT public.has_permission('journal', 'update')));

-- Clients only write the draft's own fields; numbering, status and posting stamps belong to the RPCs.
REVOKE INSERT, UPDATE ON public.t_journals FROM authenticated;
GRANT INSERT (journal_date, kind, memo, reference) ON public.t_journals TO authenticated;
GRANT UPDATE (journal_date, kind, memo, reference) ON public.t_journals TO authenticated;
REVOKE UPDATE (last_journal_id) ON public.t_recurring_journals FROM authenticated;
REVOKE UPDATE ON public.t_recurring_journals FROM authenticated;
GRANT UPDATE (name, memo, frequency, next_run, end_date, is_active) ON public.t_recurring_journals TO authenticated;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.guard_journal(), public.guard_journal_line(), public.guard_account_entries(),
  public.user_can(uuid, text, text), public.notify_users(text, text, text, text, text), public.notify_user(uuid, text, text, text),
  public.posting_period(date, boolean), public.journal_check(bigint, boolean), public.gl_post_journal(bigint, boolean),
  public.gl_create(text, date, text, text, text, bigint, jsonb, boolean), public.gl_reverse(bigint, date, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.submit_journal(bigint), public.decide_journal(bigint, boolean, text),
  public.reverse_journal(bigint, date, text), public.run_recurring_journals(date), public.can_read_ledger(),
  public.can_edit_journal(bigint) TO authenticated;
