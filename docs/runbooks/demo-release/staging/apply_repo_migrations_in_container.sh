#!/bin/sh
# STAGING ONLY — runs inside the isolated container paax_verify_pg: applies every repo migration except the demo
# one into the container's `postgres` database, to produce a production-like schema for dry-running the Windows
# backup/restore scripts. Never run against production.
set -u
for f in /tmp/mig/*.sql; do
  case "$f" in *20261030000000_demo_sessions.sql) continue;; esac
  psql -U postgres -d postgres -q -v ON_ERROR_STOP=0 -f "$f" 2>&1 | grep -E 'ERROR' | sed "s|^|$(basename "$f"): |" | head -3
done
echo APPLIED
