#!/bin/bash
cd "$(dirname "$0")" || exit 1
./run.sh >/dev/null 2>&1; ./run.sh 2>&1 | grep -E "ERROR|FAIL|failed" | head -5
export PGPASSWORD=postgres
psql -h 127.0.0.1 -p 55611 -U postgres -v ON_ERROR_STOP=1 -Atc "select public.seed_demo_data()" 2>&1 | head -12
