ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS banned_until timestamptz, ADD COLUMN IF NOT EXISTS email_change_token_new text,
  ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
CREATE TABLE IF NOT EXISTS auth.identities (id uuid PRIMARY KEY, user_id uuid REFERENCES auth.users ON DELETE CASCADE, provider_id text,
  identity_data jsonb, provider text, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz);
CREATE TABLE IF NOT EXISTS storage.buckets (id text PRIMARY KEY, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
CREATE TABLE IF NOT EXISTS storage.objects (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bucket_id text, name text, owner uuid);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS
  $$ SELECT (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
GRANT USAGE ON SCHEMA public, auth TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER TABLE auth.users OWNER TO postgres;
ALTER TABLE auth.identities OWNER TO postgres;
ALTER TABLE storage.buckets OWNER TO postgres;
ALTER TABLE storage.objects OWNER TO postgres;
GRANT ALL ON SCHEMA auth, storage TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA auth, storage TO postgres;
GRANT ALL ON storage.objects TO anon, authenticated; -- hosted Supabase default; RLS is the only gate
GRANT supabase_auth_admin TO postgres; -- lets tests act as GoTrue
