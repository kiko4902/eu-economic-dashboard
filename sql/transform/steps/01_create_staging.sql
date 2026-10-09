-- Staging table for one indicator's raw rows, filled by sql/transform/NN_<indicator>.sql.
-- Temporary and dropped when the transaction ends; dropped first in case an earlier indicator
-- ran in the same transaction (e.g. in tests).
DROP TABLE IF EXISTS pg_temp.stg_source, pg_temp.stg_observation;

CREATE TEMP TABLE stg_source (
    geo         text    NOT NULL,
    time_period text    NOT NULL,
    obs_value   numeric,
    obs_flag    text
) ON COMMIT DROP;
