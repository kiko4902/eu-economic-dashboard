-- Read-only login role for Power BI: SELECT on the analytics views only, no access to the raw
-- and warehouse schemas. Idempotent: creates the role if needed and re-applies its settings and
-- grants. Run after powerbi_reader_password.sql in the same transaction.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'powerbi_reader') THEN
        CREATE ROLE powerbi_reader;
    END IF;
    EXECUTE format(
        'ALTER ROLE powerbi_reader WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT '
        'NOREPLICATION PASSWORD %L',
        current_setting('pipeline.powerbi_reader_password')
    );
END;
$$;

-- Sessions of this role are read-only even if a grant is added by mistake later.
ALTER ROLE powerbi_reader SET default_transaction_read_only = on;

-- No access to the pipeline layers (schemas created by the pipeline owner grant nothing to
-- PUBLIC, so this only removes grants that might have been added by hand).
REVOKE ALL ON SCHEMA raw, warehouse FROM powerbi_reader;
REVOKE ALL ON ALL TABLES IN SCHEMA raw, warehouse FROM powerbi_reader;

-- Read access to the analytics views, including views created later by the pipeline owner.
GRANT USAGE ON SCHEMA analytics TO powerbi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO powerbi_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO powerbi_reader;
