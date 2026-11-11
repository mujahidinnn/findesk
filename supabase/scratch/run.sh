#!/bin/bash
# Dry run: a throwaway Postgres (in memory, no volume) gets every migration, then every smoke test.
#   supabase/scratch/run.sh            migrations + smoke tests
#   supabase/scratch/run.sh types      also regenerate src/integrations/supabase/types.ts
#   supabase/scratch/run.sh stop       remove the container
# The container stays up afterwards for psql -h 127.0.0.1 -p 55611 -U postgres (password postgres).
cd "$(dirname "$0")/.." || exit 1
IMAGE=public.ecr.aws/supabase/postgres:17.6.1.171
export PGPASSWORD=postgres
docker rm -f findesk-scratch >/dev/null 2>&1
[ "$1" = stop ] && exit 0
docker run -d --rm --name findesk-scratch --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=postgres \
  -p 127.0.0.1:55611:5432 "$IMAGE" >/dev/null || exit 1
for _ in $(seq 1 40); do psql -h 127.0.0.1 -p 55611 -U postgres -Atc "select 1" >/dev/null 2>&1 && break; sleep 2; done
sleep 2
P="psql -h 127.0.0.1 -p 55611 -v ON_ERROR_STOP=1 -q"
$P -U supabase_admin -d postgres -f scratch/prelude.sql 2>&1 | grep -v NOTICE
for f in migrations/*.sql; do
  $P -U postgres -1 -f "$f" 2>&1 | grep -v NOTICE
  [ "${PIPESTATUS[0]}" = 0 ] || { echo "MIGRATION FAILED: $f"; exit 1; }
done
echo "migrations ok"
fail=0
for t in tests/*.sql; do
  $P -U postgres -f "$t" 2>&1 | grep -v NOTICE | tail -3
  [ "${PIPESTATUS[0]}" = 0 ] || fail=1
done
if [ "$1" = types ]; then
  docker rm -f findesk-meta >/dev/null 2>&1
  docker run -d --name findesk-meta --network host -e PG_META_PORT=55612 -e PG_META_DB_HOST=127.0.0.1 -e PG_META_DB_PORT=55611 \
    -e PG_META_DB_NAME=postgres -e PG_META_DB_USER=postgres -e PG_META_DB_PASSWORD=postgres \
    public.ecr.aws/supabase/postgres-meta:v0.99.0 >/dev/null
  for _ in $(seq 1 15); do
    code=$(curl -s -m 30 "http://127.0.0.1:55612/generators/typescript?included_schemas=public" -o "${TMPDIR:-/tmp}/findesk-types.ts" -w "%{http_code}")
    [ "$code" = 200 ] && break; sleep 2
  done
  docker rm -f findesk-meta >/dev/null
  [ "$code" = 200 ] && cp "${TMPDIR:-/tmp}/findesk-types.ts" ../src/integrations/supabase/types.ts && echo "types ok" || { echo "typegen failed"; fail=1; }
fi
exit $fail
