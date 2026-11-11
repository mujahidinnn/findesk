#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
export PGPASSWORD=postgres
P="psql -h 127.0.0.1 -p 55611 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "select public.superadmin_reset_data()" >/dev/null && $P -Atc "select public.seed_demo_data()"
