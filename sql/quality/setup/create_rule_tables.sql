-- Check configuration from seeds/quality_rules.csv and seeds/known_gaps.csv, loaded fresh on
-- every run into temp tables (dropped at the end of the transaction), so a rule or known gap
-- removed from the CSV can never linger in the database. Dropped first in case checks already
-- ran in the same transaction (e.g. in tests).
DROP TABLE IF EXISTS pg_temp.qc_rule, pg_temp.qc_known_gap, pg_temp.qc_missing_period;

CREATE TEMP TABLE qc_rule (
    indicator_code text PRIMARY KEY,
    min_value      numeric NOT NULL,
    max_value      numeric NOT NULL CHECK (max_value > min_value),
    max_lag_months integer CHECK (max_lag_months > 0)
) ON COMMIT DROP;

CREATE TEMP TABLE qc_known_gap (
    indicator_code text NOT NULL,
    country_code   text NOT NULL,
    gap_type       text NOT NULL CHECK (gap_type IN ('no_series', 'missing_periods')),
    from_date      date,
    to_date        date,
    reason         text NOT NULL,
    CHECK ((gap_type = 'no_series') = (from_date IS NULL AND to_date IS NULL)),
    CHECK (from_date <= to_date)
) ON COMMIT DROP;
