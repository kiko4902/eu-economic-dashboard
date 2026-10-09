-- Documented known gaps (seeds/known_gaps.csv) as used by the latest data quality run: the
-- expected missing data that the quality checks accept.
CREATE OR REPLACE VIEW analytics.v_known_gaps AS
SELECT g.indicator_code,
       g.country_code,
       g.gap_type,
       CASE g.gap_type
           WHEN 'no_series' THEN 'No data at all'
           ELSE 'Missing ' || g.from_period
                || CASE WHEN g.to_period <> g.from_period THEN ' to ' || g.to_period ELSE '' END
       END          AS gap_description,
       g.from_period,
       g.to_period,
       g.reason,
       g.run_id
FROM quality.check_known_gap AS g
WHERE g.run_id = (SELECT max(run_id) FROM quality.check_run);

COMMENT ON VIEW analytics.v_known_gaps IS
    'Known data gaps (Eurostat does not publish the data) accepted by the latest quality run.';
COMMENT ON COLUMN analytics.v_known_gaps.gap_type IS
    'no_series: no data for this country; missing_periods: from_period..to_period missing.';
COMMENT ON COLUMN analytics.v_known_gaps.gap_description IS 'Readable summary of the gap.';
COMMENT ON COLUMN analytics.v_known_gaps.reason IS 'Why the data is missing.';
