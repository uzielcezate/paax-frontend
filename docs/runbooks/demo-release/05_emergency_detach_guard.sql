-- EMERGENCY: detach the demo guard from every API request (seconds). Safe to run at any time.
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';
select rolconfig from pg_roles where rolname = 'authenticator';
