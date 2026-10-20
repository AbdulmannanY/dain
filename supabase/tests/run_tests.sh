#!/usr/bin/env bash
# Runs the schema tests on a throwaway database.
# Usage: PGHOST=... PGPORT=... PGUSER=postgres bash supabase/tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=dain_test
psql -qc "drop database if exists $DB" -c "create database $DB" >/dev/null
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/supabase_stub.sql
for f in migrations/*.sql; do psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"; done
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/ledger_flow_test.sql
psql -qc "drop database $DB" >/dev/null
