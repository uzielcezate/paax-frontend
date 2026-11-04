-- Platform fixtures for the EMPTY scratch database used by Verify-Restore.ps1 (local only, not application data).
-- Supabase keeps extensions in schema `extensions`, realtime uses publication `supabase_realtime`, and the dumps
-- reference schemas private / supabase_functions / vault; recreate them so the schema dump restores cleanly.
create schema if not exists extensions;
create schema if not exists supabase_functions;
create schema if not exists private;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;
create extension if not exists pg_trgm with schema extensions;   -- trigram indexes on search columns
create extension if not exists supabase_vault cascade;
create publication supabase_realtime;
