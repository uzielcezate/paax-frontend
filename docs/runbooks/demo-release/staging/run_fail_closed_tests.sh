#!/usr/bin/env bash
# STAGING ONLY — proves the Option A migration is fail-closed on the local Supabase stack.
# Usage (from the worktree root): bash docs/runbooks/demo-release/staging/run_fail_closed_tests.sh
# Test 2: pg_cron cannot be installed  -> whole transaction rolls back (no table, no functions, no hook).
# Test 3: cron.schedule() fails        -> whole transaction rolls back (extension pre-installed stays).
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: keep container paths like /usr/... intact
DB=supabase_db_web-demo-mode
RB=docs/runbooks/demo-release
# The apply itself runs as `postgres`, exactly like the production SQL editor (not a superuser on Supabase).
psql_file() { docker exec -i "$DB" psql -U postgres -q -v ON_ERROR_STOP=1 -f - < "$1"; }
state()     { docker exec -i "$DB" psql -U postgres -q -f - < "$RB/staging/state.sql" 2>&1 | sed 's/^psql:<stdin>:[0-9]*: NOTICE:  //'; }
sql()       { docker exec "$DB" psql -U postgres -At -q -c "$1"; }
# Fault injection needs the image superuser (owner of the cron extension objects).
sqla()      { docker exec "$DB" psql -U supabase_admin -d postgres -At -q -c "$1"; }

echo "== reset to production pre-state (rollback + drop pg_cron, remove staging users)"
docker exec -i "$DB" psql -U postgres -q -f - < "$RB/03_rollback_demo_guard.sql" >/dev/null 2>&1
sql "delete from auth.users where email like '%staging%'"
sql "drop extension if exists pg_cron cascade"
state

echo "== TEST 2: make 'create extension pg_cron' impossible (remove it from shared_preload_libraries), then apply"
# Same failure production would show if pg_cron were not preloaded: 'pg_cron can only be loaded via shared_preload_libraries'.
wait_db() { for i in $(seq 1 30); do docker exec "$DB" pg_isready -U postgres -q && sleep 2 && return 0; sleep 2; done; echo "db not ready"; return 1; }
PRELOAD_ORIG=$(sql "show shared_preload_libraries")
PRELOAD_NO_CRON=$(echo "$PRELOAD_ORIG" | sed 's/, *pg_cron//; s/pg_cron, *//')
echo "preload without pg_cron: $PRELOAD_NO_CRON"
# shared_preload_libraries is a GUC list: pass unquoted identifiers (a single quoted string would be ONE library name)
sqla "alter system set shared_preload_libraries = $PRELOAD_NO_CRON"
docker restart "$DB" >/dev/null && wait_db
echo "shared_preload_libraries now: $(sql 'show shared_preload_libraries')"
if psql_file "$RB/04_apply_option_a.sql" 2>&1 | grep -E "ERROR|ROLLBACK" | head -3; then :; fi
echo "-- after failed apply (expect: absent / 0 / 0 / pg_cron-absent / hook-off):"
state
sqla "alter system reset shared_preload_libraries"
docker restart "$DB" >/dev/null && wait_db
echo "shared_preload_libraries restored: $(sql 'show shared_preload_libraries')"

echo "== TEST 3: pg_cron present but cron.schedule() broken, then apply"
sql "create extension if not exists pg_cron with schema pg_catalog" >/dev/null
sqla "alter function cron.schedule(text, text, text) rename to schedule_disabled_for_test"
if psql_file "$RB/04_apply_option_a.sql" 2>&1 | grep -E "ERROR|ROLLBACK" | head -3; then :; fi
echo "-- after failed apply (expect: absent / 0 / 1 / no-jobs / hook-off):"
state
sqla "alter function cron.schedule_disabled_for_test(text, text, text) rename to schedule"

echo "== TEST 3b: cron.schedule() 'succeeds' but leaves no active job -> explicit assertion must abort"
sqla "alter function cron.schedule(text, text, text) rename to schedule_real"
sqla "create function cron.schedule(text, text, text) returns bigint language sql as \$f\$ select 424242::bigint \$f\$"
sqla "grant execute on function cron.schedule(text, text, text) to postgres"
if psql_file "$RB/04_apply_option_a.sql" 2>&1 | grep -E "ERROR|ROLLBACK" | head -3; then :; fi
echo "-- after failed apply (expect: absent / 0 / 1 / no-jobs / hook-off):"
state
sqla "drop function cron.schedule(text, text, text)"
sqla "alter function cron.schedule_real(text, text, text) rename to schedule"

echo "== TEST 1 (again, after the failures): clean apply must still succeed"
if psql_file "$RB/04_apply_option_a.sql" 2>&1 | grep -E "ERROR" | head -3; then :; fi
echo "-- after apply (expect: public.demo_sessions / 3 / 1 / paax_demo_cleanup:true / hook-on):"
state
echo "== done (local stack left in the applied state)"
