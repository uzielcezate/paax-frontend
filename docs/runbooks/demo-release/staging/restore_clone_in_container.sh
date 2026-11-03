#!/bin/sh
# STAGING ONLY — runs inside the isolated container paax_verify_pg: rebuilds its `postgres` database from a
# decrypted production backup copied to /tmp/clone (managed_schema.sql, schema.sql, data.sql), producing an exact
# clone of production for rehearsing 04 / 02 / 03. Never run against production.
set -u
P="psql -U supabase_admin -d postgres -q -v ON_ERROR_STOP=0"
$P -c "drop schema if exists auth cascade; drop schema if exists storage cascade; create schema auth; create schema storage; grant all on schema auth to supabase_auth_admin; grant all on schema storage to supabase_storage_admin; create schema if not exists supabase_functions; create schema if not exists private; alter schema private owner to postgres; create extension if not exists pg_trgm with schema extensions; create extension if not exists pg_stat_statements with schema extensions;" 2>&1 | grep ERROR
echo "== managed_schema (1st pass)"; $P -f /tmp/clone/managed_schema.sql 2>&1 | grep -E 'ERROR' | sort | uniq -c
echo "== schema";                    $P -f /tmp/clone/schema.sql         2>&1 | grep -E 'ERROR' | sort | uniq -c
echo "== managed_schema (2nd pass: the two auth triggers)"; $P -f /tmp/clone/managed_schema.sql 2>&1 | grep -E 'ERROR' | grep -v 'already exists' | sort | uniq -c
# data is loaded with triggers disabled (session_replication_role = replica) so the signup trigger does not
# fabricate profile rows before the real ones arrive — same as pg_restore --disable-triggers.
echo "== data (triggers disabled)";  $P -c "set session_replication_role = replica;" -f /tmp/clone/data.sql 2>&1 | grep -E 'ERROR' | sort | uniq -c
echo "== triggers on auth.users:";   psql -U supabase_admin -d postgres -At -c "select tgname from pg_trigger where tgrelid='auth.users'::regclass and not tgisinternal order by 1"
mkdir -p /tmp/paax && cp /tmp/clone/06.sql /tmp/paax/06.sql      # same path as the production run -> identical NOTICE prefixes
sed -i '1s/^\xEF\xBB\xBF//' /tmp/clone/fp_production.txt          # strip the UTF-8 BOM PowerShell wrote
echo "== fingerprint (postgres db)"; psql -U postgres -d postgres -At -q -v ON_ERROR_STOP=1 -f /tmp/paax/06.sql > /tmp/clone/fp_clone.txt 2>&1
if diff /tmp/clone/fp_production.txt /tmp/clone/fp_clone.txt > /dev/null; then echo "CLONE FINGERPRINT IDENTICAL TO PRODUCTION"; else echo "CLONE FINGERPRINT DIFFERS:"; diff /tmp/clone/fp_production.txt /tmp/clone/fp_clone.txt | head -20; fi
