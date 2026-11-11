CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE TABLE public.m_settings (
    id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    company_name text NOT NULL DEFAULT 'FinDesk',
    legal_name text,
    address text,
    phone text,
    email text,
    npwp text,
    is_pkp boolean NOT NULL DEFAULT true,
    logo_url text,
    timezone text NOT NULL DEFAULT 'Asia/Jakarta',
    base_currency text NOT NULL DEFAULT 'IDR' CHECK (base_currency ~ '^[A-Z]{3}$'),
    require_journal_approval boolean NOT NULL DEFAULT true,
    approval_threshold numeric(18,2) NOT NULL DEFAULT 10000000 CHECK (approval_threshold >= 0),
    invoice_footer text,
    demo_mode boolean NOT NULL DEFAULT false,
    doc_prefixes jsonb NOT NULL DEFAULT
      '{"journal":"JV","sales_invoice":"INV","sales_credit":"CN","purchase_bill":"BILL","purchase_debit":"DN",
        "payment_in":"RCV","payment_out":"PAY","cash_in":"CI","cash_out":"CO","transfer":"TRF","expense":"EXP",
        "asset":"FA","depreciation":"DEP","vat":"VAT","fx":"FX","closing":"CLS","budget":"BGT"}',
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.m_settings DEFAULT VALUES;

CREATE TABLE public.m_roles (
    id bigint PRIMARY KEY,
    role_name text NOT NULL UNIQUE,
    rank integer NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.m_features (
    id bigint PRIMARY KEY,
    feature_key text NOT NULL UNIQUE,
    feature_name text NOT NULL,
    icon_name text,
    path text
);

CREATE TABLE public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
    role_id bigint REFERENCES public.m_roles ON DELETE SET NULL,
    full_name text,
    avatar_url text,
    locale text CHECK (locale IN ('id', 'en')),
    employee_code text UNIQUE,
    is_superadmin boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profiles_role_id_idx ON public.profiles (role_id);

CREATE TABLE public.t_role_permissions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id bigint NOT NULL REFERENCES public.m_roles ON DELETE CASCADE,
    feature_id bigint NOT NULL REFERENCES public.m_features ON DELETE CASCADE,
    can_create boolean NOT NULL DEFAULT false,
    can_read boolean NOT NULL DEFAULT false,
    can_update boolean NOT NULL DEFAULT false,
    can_delete boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (role_id, feature_id)
);
CREATE INDEX t_role_permissions_feature_idx ON public.t_role_permissions (feature_id);

CREATE TABLE public.t_user_access_override (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.profiles ON DELETE CASCADE,
    feature_id bigint NOT NULL REFERENCES public.m_features ON DELETE CASCADE,
    can_create boolean,
    can_read boolean,
    can_update boolean,
    can_delete boolean,
    is_override_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid() REFERENCES public.profiles ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, feature_id)
);
CREATE INDEX t_user_access_override_feature_idx ON public.t_user_access_override (feature_id);
CREATE INDEX t_user_access_override_created_by_idx ON public.t_user_access_override (created_by);

CREATE TABLE public.t_audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id uuid REFERENCES public.profiles ON DELETE SET NULL,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    detail jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_audit_log_created_idx ON public.t_audit_log (created_at DESC);
CREATE INDEX t_audit_log_actor_idx ON public.t_audit_log (actor_id);
CREATE INDEX t_audit_log_entity_idx ON public.t_audit_log (entity_type, entity_id);

CREATE TABLE public.t_error_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid,
    source text NOT NULL,
    message text NOT NULL,
    context jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_error_log_created_idx ON public.t_error_log (created_at DESC);
CREATE INDEX t_error_log_user_idx ON public.t_error_log (user_id, created_at DESC);

CREATE TABLE public.t_notifications (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.profiles ON DELETE CASCADE,
    title text NOT NULL,
    body text,
    link text,
    is_read boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid DEFAULT auth.uid(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX t_notifications_user_idx ON public.t_notifications (user_id, created_at DESC);

CREATE TRIGGER trg_settings_updated_at BEFORE UPDATE ON public.m_settings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_role_perms_updated_at BEFORE UPDATE ON public.t_role_permissions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_override_updated_at BEFORE UPDATE ON public.t_user_access_override FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_notifications_updated_at BEFORE UPDATE ON public.t_notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.m_roles (id, role_name, rank) VALUES
  (1, 'Admin', 1),
  (2, 'Finance Manager', 2),
  (3, 'Accountant', 3),
  (4, 'Finance Staff', 4),
  (5, 'Auditor', 5),
  (6, 'Employee', 6);

INSERT INTO public.m_features (id, feature_key, feature_name, icon_name, path) VALUES
  (1,  'dashboard',   'Dashboard',              'LayoutDashboard', '/'),
  (2,  'journal',     'Jurnal Umum',            'BookOpen',        '/journals'),
  (3,  'account',     'Bagan Akun',             'ListTree',        '/accounts'),
  (4,  'period',      'Periode & Tutup Buku',   'CalendarCheck',   '/periods'),
  (5,  'receivable',  'Penjualan & Piutang',    'Receipt',         '/sales/invoices'),
  (6,  'payable',     'Pembelian & Hutang',     'FileInput',       '/purchases/bills'),
  (7,  'partner',     'Pelanggan & Pemasok',    'Users',           '/partners'),
  (8,  'cash-bank',   'Kas & Bank',             'Landmark',        '/cash'),
  (9,  'reconcile',   'Rekonsiliasi Bank',      'GitCompareArrows','/reconcile'),
  (10, 'tax',         'Pajak',                  'Percent',         '/tax'),
  (11, 'asset',       'Aset Tetap',             'Building2',       '/assets'),
  (12, 'budget',      'Anggaran',               'Target',          '/budgets'),
  (13, 'expense',     'Reimburse',              'Wallet',          '/expenses'),
  (14, 'approval',    'Persetujuan',            'ShieldCheck',     '/approvals'),
  (15, 'reports',     'Laporan Keuangan',       'ChartColumn',     '/reports'),
  (16, 'audit',       'Jejak Audit',            'History',         '/audit'),
  (17, 'settings',    'Pengaturan',             'Settings',        '/settings'),
  (18, 'users',       'Pengguna & Akses',       'UserCog',         '/settings?tab=users'),
  (19, 'expense-all', 'Reimburse Semua Karyawan','UsersRound',     NULL);

INSERT INTO public.t_role_permissions (role_id, feature_id, can_create, can_read, can_update, can_delete)
SELECT r.id, f.id, m.perm LIKE '%C%', m.perm LIKE '%R%', m.perm LIKE '%U%', m.perm LIKE '%D%'
  FROM (VALUES
    ('dashboard',   '',    'R', 'R',   'R',    'R',    'CRUD'),
    ('journal',     '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('account',     '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('period',      '',    'R', 'R',   'R',    'RU',   'CRUD'),
    ('receivable',  '',    'R', 'CRU', 'CRUD', 'CRUD', 'CRUD'),
    ('payable',     '',    'R', 'CRU', 'CRUD', 'CRUD', 'CRUD'),
    ('partner',     '',    'R', 'CRU', 'CRUD', 'CRUD', 'CRUD'),
    ('cash-bank',   '',    'R', 'CRU', 'CRUD', 'CRUD', 'CRUD'),
    ('reconcile',   '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('tax',         '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('asset',       '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('budget',      '',    'R', 'R',   'CRU',  'CRUD', 'CRUD'),
    ('expense',     'CR',  'R', 'CRU', 'CRU',  'CRUD', 'CRUD'),
    ('expense-all', '',    'R', 'R',   'R',    'R',    'R'),
    ('approval',    '',    'R', '',    'RU',   'RU',   'CRUD'),
    ('reports',     '',    'R', 'R',   'R',    'R',    'CRUD'),
    ('audit',       '',    'R', '',    'R',    'R',    'CRUD'),
    ('settings',    '',    'R', 'R',   'R',    'RU',   'CRUD'),
    ('users',       '',    '',  '',    '',     'R',    'CRUD')
  ) AS v(feature_key, employee, auditor, staff, accountant, manager, admin)
  JOIN public.m_features f ON f.feature_key = v.feature_key
  CROSS JOIN LATERAL (VALUES
    ('Employee', v.employee),
    ('Auditor', v.auditor),
    ('Finance Staff', v.staff),
    ('Accountant', v.accountant),
    ('Finance Manager', v.manager),
    ('Admin', v.admin)
  ) AS m(role_name, perm)
  JOIN public.m_roles r ON r.role_name = m.role_name
 WHERE m.perm <> '';

CREATE FUNCTION public.is_banned() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND banned_until > now());
$$;

CREATE FUNCTION public.is_superadmin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE((SELECT is_superadmin FROM profiles WHERE id = auth.uid()), false);
$$;

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT NOT is_banned() AND EXISTS (
    SELECT 1 FROM profiles p JOIN m_roles r ON r.id = p.role_id
     WHERE p.id = auth.uid() AND r.role_name = 'Admin'
  );
$$;

CREATE FUNCTION public.has_permission(p_feature_key text, p_action text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT NOT is_banned() AND COALESCE(
    (SELECT CASE p_action
       WHEN 'create' THEN o.can_create WHEN 'read' THEN o.can_read
       WHEN 'update' THEN o.can_update WHEN 'delete' THEN o.can_delete END
       FROM t_user_access_override o JOIN m_features f ON f.id = o.feature_id
      WHERE o.user_id = auth.uid() AND f.feature_key = p_feature_key AND o.is_override_active),
    (SELECT CASE p_action
       WHEN 'create' THEN rp.can_create WHEN 'read' THEN rp.can_read
       WHEN 'update' THEN rp.can_update WHEN 'delete' THEN rp.can_delete END
       FROM t_role_permissions rp
       JOIN m_features f ON f.id = rp.feature_id
       JOIN profiles p ON p.role_id = rp.role_id
      WHERE p.id = auth.uid() AND f.feature_key = p_feature_key),
    false
  );
$$;

CREATE FUNCTION public.has_any_access() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT NOT is_banned() AND (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role_id IS NOT NULL)
    OR EXISTS (SELECT 1 FROM t_user_access_override WHERE user_id = auth.uid() AND is_override_active));
$$;

CREATE FUNCTION public.my_rank() RETURNS integer
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT r.rank FROM profiles p JOIN m_roles r ON r.id = p.role_id WHERE p.id = auth.uid();
$$;

CREATE FUNCTION public.outranks(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT is_superadmin() OR (
    my_rank() IS NOT NULL
    AND NOT COALESCE((SELECT is_superadmin FROM profiles WHERE id = p_user_id), false)
    AND COALESCE((SELECT r.rank FROM profiles p JOIN m_roles r ON r.id = p.role_id WHERE p.id = p_user_id), 2147483647) > my_rank());
$$;

CREATE FUNCTION public.can_grant(p_feature_id bigint, p_create boolean, p_read boolean, p_update boolean, p_delete boolean)
RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT (NOT COALESCE(p_create, false) OR has_permission(f.feature_key, 'create'))
     AND (NOT COALESCE(p_read, false)   OR has_permission(f.feature_key, 'read'))
     AND (NOT COALESCE(p_update, false) OR has_permission(f.feature_key, 'update'))
     AND (NOT COALESCE(p_delete, false) OR has_permission(f.feature_key, 'delete'))
    FROM m_features f WHERE f.id = p_feature_id;
$$;

CREATE FUNCTION public.company_today() RETURNS date
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(NULLIF(current_setting('findesk.today', true), '')::date,
                  (now() AT TIME ZONE COALESCE((SELECT timezone FROM m_settings), 'Asia/Jakarta'))::date);
$$;

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO profiles (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
             NULLIF(NEW.raw_user_meta_data->>'name', ''),
             split_part(NEW.email, '@', 1)),
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'avatar_url', ''),
             NULLIF(NEW.raw_user_meta_data->>'picture', ''))
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name  = EXCLUDED.full_name,
        avatar_url = COALESCE(EXCLUDED.avatar_url, profiles.avatar_url);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE FUNCTION public.guard_profile_role_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_actor_rank int;
  v_old_rank   int;
  v_new_rank   int;
BEGIN
  IF auth.role() = 'service_role' OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT has_permission('users', 'update') THEN
      NEW.role_id := NULL;
      NEW.employee_code := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.employee_code IS DISTINCT FROM OLD.employee_code
     AND NOT (has_permission('users', 'update') AND (NEW.id = auth.uid() OR outranks(NEW.id))) THEN
    RAISE EXCEPTION 'Only a user manager can change the employee code' USING errcode = '42501';
  END IF;

  IF NEW.role_id IS NOT DISTINCT FROM OLD.role_id THEN
    RETURN NEW;
  END IF;

  IF auth.uid() = NEW.id THEN
    RAISE EXCEPTION 'You cannot change your own role' USING errcode = '42501';
  END IF;

  SELECT r.rank INTO v_actor_rank
    FROM profiles p JOIN m_roles r ON r.id = p.role_id WHERE p.id = auth.uid();
  IF v_actor_rank IS NULL THEN
    RAISE EXCEPTION 'Only someone with an assigned role can change roles' USING errcode = '42501';
  END IF;

  v_old_rank := COALESCE((SELECT rank FROM m_roles WHERE id = OLD.role_id), 2147483647);
  v_new_rank := COALESCE((SELECT rank FROM m_roles WHERE id = NEW.role_id), 2147483647);

  IF v_old_rank <= v_actor_rank THEN
    RAISE EXCEPTION 'You can only change the role of someone below your own role' USING errcode = '42501';
  END IF;
  IF v_new_rank <= v_actor_rank THEN
    RAISE EXCEPTION 'You cannot assign a role at or above your own rank' USING errcode = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_profile_role_insert BEFORE INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role_change();
CREATE TRIGGER trg_guard_profile_role_change BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_role_change();

CREATE FUNCTION public.guard_superadmin_flag() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.is_superadmin IS DISTINCT FROM OLD.is_superadmin
     AND auth.uid() IS NOT NULL AND NOT is_superadmin() THEN
    RAISE EXCEPTION 'Only a superadmin can change that flag' USING errcode = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_superadmin_flag BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_superadmin_flag();

-- Never copy a secret into the log.
CREATE FUNCTION public.audit_row_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_new jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
  v_old jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  v_row jsonb := COALESCE(v_new, v_old);
BEGIN
  INSERT INTO t_audit_log (actor_id, action, entity_type, entity_id, detail)
  VALUES (
    auth.uid(), lower(TG_OP), TG_ARGV[0], COALESCE(v_row->>'id', '-'),
    CASE TG_OP
      WHEN 'INSERT' THEN jsonb_build_object('after', v_new)
      WHEN 'DELETE' THEN jsonb_build_object('before', v_old)
      ELSE jsonb_build_object('before', v_old, 'after', v_new)
    END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_profiles AFTER UPDATE ON public.profiles
  FOR EACH ROW WHEN (OLD.role_id IS DISTINCT FROM NEW.role_id OR OLD.is_superadmin IS DISTINCT FROM NEW.is_superadmin
                     OR OLD.employee_code IS DISTINCT FROM NEW.employee_code)
  EXECUTE FUNCTION public.audit_row_change('profile');
CREATE TRIGGER trg_audit_role_permission AFTER INSERT OR UPDATE OR DELETE ON public.t_role_permissions
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('role_permission');
CREATE TRIGGER trg_audit_access_override AFTER INSERT OR UPDATE OR DELETE ON public.t_user_access_override
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('access_override');
CREATE TRIGGER trg_audit_settings AFTER UPDATE ON public.m_settings
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change('settings');

CREATE FUNCTION public.log_client_error(p_source text, p_message text, p_context jsonb DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  h    json := NULLIF(current_setting('request.headers', true), '')::json;
  v_ip text := left(COALESCE(h->>'cf-connecting-ip', trim(split_part(h->>'x-forwarded-for', ',', 1))), 64);
BEGIN
  IF auth.uid() IS NOT NULL THEN
    IF (SELECT count(*) FROM t_error_log
         WHERE user_id = auth.uid() AND created_at > now() - interval '1 minute') >= 20 THEN
      RETURN;
    END IF;
  ELSIF (SELECT count(*) FILTER (WHERE context->>'ip' IS NOT DISTINCT FROM v_ip) >= 20 OR count(*) >= 600
           FROM t_error_log WHERE user_id IS NULL AND created_at > now() - interval '1 minute') THEN
    RETURN;
  END IF;
  INSERT INTO t_error_log (user_id, source, message, context)
  VALUES (auth.uid(), left(p_source, 64), left(p_message, 1000),
          CASE WHEN jsonb_typeof(p_context) = 'object' AND length(p_context::text) <= 4000 THEN p_context ELSE '{}' END
            || jsonb_build_object('ip', v_ip));
END;
$$;

CREATE FUNCTION public.get_users_with_email()
RETURNS TABLE (id uuid, full_name text, email text, role_id bigint, role_name text, avatar_url text,
               employee_code text, created_at timestamptz, banned_until timestamptz, is_superadmin boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
  SELECT p.id, p.full_name,
         CASE WHEN public.is_admin() THEN u.email::text ELSE '' END,
         p.role_id, r.role_name, p.avatar_url, p.employee_code, p.created_at, u.banned_until, p.is_superadmin
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    LEFT JOIN public.m_roles r ON r.id = p.role_id
   WHERE public.has_any_access() AND (NOT p.is_superadmin OR public.is_superadmin())
   ORDER BY p.created_at;
$$;

-- Creates/resets the superadmin login; SQL editor only, never exposed to API roles.
CREATE FUNCTION public.superadmin_bootstrap(p_email text, p_password text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_id uuid;
BEGIN
  IF length(COALESCE(p_password, '')) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters';
  END IF;

  SELECT id INTO v_id FROM auth.users WHERE email = p_email;
  IF v_id IS NOT NULL THEN
    UPDATE auth.users
       SET encrypted_password = crypt(p_password, gen_salt('bf')),
           email_confirmed_at = COALESCE(email_confirmed_at, now()),
           banned_until = NULL, updated_at = now()
     WHERE id = v_id;
  ELSE
    v_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      p_email, crypt(p_password, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', '{"full_name":"Superadmin"}',
      now(), now(), '', '', '', ''
    );
  END IF;

  INSERT INTO auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  SELECT gen_random_uuid(), v_id, v_id::text,
         jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
         'email', NULL, now(), now()
   WHERE NOT EXISTS (SELECT 1 FROM auth.identities WHERE user_id = v_id AND provider = 'email');

  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  UPDATE profiles
     SET full_name = COALESCE(full_name, 'Superadmin'), is_superadmin = true,
         role_id = COALESCE(role_id, (SELECT id FROM m_roles WHERE role_name = 'Admin'))
   WHERE id = v_id;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_id;
END;
$$;

ALTER TABLE public.m_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.m_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_user_access_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_error_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.t_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY settings_select ON public.m_settings FOR SELECT TO authenticated
  USING ((SELECT public.has_any_access()));
CREATE POLICY settings_update ON public.m_settings FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('settings', 'update')))
  WITH CHECK ((SELECT public.has_permission('settings', 'update')));

CREATE POLICY roles_select ON public.m_roles FOR SELECT TO authenticated USING (true);
CREATE POLICY features_select ON public.m_features FOR SELECT TO authenticated USING (true);
CREATE POLICY role_perms_select ON public.t_role_permissions FOR SELECT TO authenticated USING (true);

CREATE POLICY overrides_select ON public.t_user_access_override FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR (SELECT public.has_permission('users', 'read')));
CREATE POLICY overrides_write ON public.t_user_access_override FOR ALL TO authenticated
  USING ((SELECT public.has_permission('users', 'update')) AND user_id <> (SELECT auth.uid()) AND public.outranks(user_id))
  WITH CHECK ((SELECT public.has_permission('users', 'update')) AND user_id <> (SELECT auth.uid()) AND public.outranks(user_id)
              AND public.can_grant(feature_id, can_create, can_read, can_update, can_delete));

CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated USING (
  id = (SELECT auth.uid())
  OR ((SELECT public.has_any_access()) AND (NOT is_superadmin OR (SELECT public.is_superadmin()))));
CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY profiles_update_admin ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT public.has_permission('users', 'update')) AND public.outranks(id))
  WITH CHECK ((SELECT public.has_permission('users', 'update')) AND public.outranks(id));

CREATE POLICY audit_select ON public.t_audit_log FOR SELECT TO authenticated USING (
  CASE
    WHEN entity_type = 'profile' AND (detail->'after'->>'is_superadmin' = 'true' OR detail->'before'->>'is_superadmin' = 'true')
      THEN (SELECT public.is_superadmin())
    WHEN entity_type IN ('access_override', 'profile', 'role_permission', 'user') THEN (SELECT public.has_permission('users', 'read'))
    ELSE (SELECT public.has_permission('settings', 'read'))
  END);

CREATE POLICY error_log_select ON public.t_error_log FOR SELECT TO authenticated
  USING ((SELECT public.is_superadmin()));

CREATE POLICY notifications_select_own ON public.t_notifications FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY notifications_update_own ON public.t_notifications FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));

-- Column grants: demo_mode changes through RPCs; profile edits are limited to these columns.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.m_settings, public.m_roles, public.m_features, public.t_role_permissions,
  public.t_audit_log, public.t_error_log, public.t_notifications, public.profiles FROM authenticated;
GRANT UPDATE (company_name, legal_name, address, phone, email, npwp, is_pkp, logo_url, timezone,
              require_journal_approval, approval_threshold, invoice_footer, doc_prefixes)
  ON public.m_settings TO authenticated;
GRANT UPDATE (full_name, avatar_url, locale, role_id, employee_code) ON public.profiles TO authenticated;
GRANT UPDATE (is_read) ON public.t_notifications TO authenticated;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_banned(), public.is_superadmin(), public.is_admin(), public.has_permission(text, text),
  public.has_any_access(), public.my_rank(), public.outranks(uuid),
  public.can_grant(bigint, boolean, boolean, boolean, boolean), public.company_today(),
  public.log_client_error(text, text, jsonb), public.get_users_with_email()
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_client_error(text, text, jsonb) TO anon;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('avatars', 'avatars', true, 1048576, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('branding', 'branding', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('attachments', 'attachments', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS avatars_public_read ON storage.objects;
CREATE POLICY avatars_public_read ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'avatars');
DROP POLICY IF EXISTS avatars_user_insert ON storage.objects;
CREATE POLICY avatars_user_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (SELECT auth.uid())::text = (storage.foldername(name))[1]);
DROP POLICY IF EXISTS avatars_user_update ON storage.objects;
CREATE POLICY avatars_user_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (SELECT auth.uid())::text = (storage.foldername(name))[1]);
DROP POLICY IF EXISTS avatars_user_delete ON storage.objects;
CREATE POLICY avatars_user_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avatars' AND (SELECT auth.uid())::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS branding_public_read ON storage.objects;
CREATE POLICY branding_public_read ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'branding');
DROP POLICY IF EXISTS branding_write ON storage.objects;
CREATE POLICY branding_write ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'branding' AND (SELECT public.has_permission('settings', 'update')))
  WITH CHECK (bucket_id = 'branding' AND (SELECT public.has_permission('settings', 'update')));

ALTER PUBLICATION supabase_realtime ADD TABLE public.t_notifications, public.m_settings;
