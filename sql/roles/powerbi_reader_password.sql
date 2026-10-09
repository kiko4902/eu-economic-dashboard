-- Pass the powerbi_reader password (from .env) to powerbi_reader.sql as a transaction-local
-- setting, so it is a bound parameter here and never part of a SQL file.
SELECT set_config('pipeline.powerbi_reader_password', :password, true);
