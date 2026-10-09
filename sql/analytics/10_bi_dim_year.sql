-- Year dimension for Power BI: one row per year from the first to the last year with any
-- observation. Relates one-to-many to every analytics view with a year column.
CREATE OR REPLACE VIEW analytics.bi_dim_year AS
WITH bounds AS (
    SELECT min(t.year) AS first_year,
           max(t.year) AS last_year
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
),
annual AS (
    SELECT DISTINCT year
    FROM analytics.v_annual_summary
)
SELECT CAST(y AS smallint)                                   AS year,
       CAST(y AS text)                                       AS year_label,
       y IN (SELECT year FROM annual)                        AS has_annual_data,
       y = (SELECT max(year) FROM annual)                    AS is_latest_annual_year
FROM bounds
CROSS JOIN LATERAL generate_series(CAST(bounds.first_year AS integer),
                                   CAST(bounds.last_year AS integer)) AS y;

COMMENT ON VIEW analytics.bi_dim_year IS
    'Power BI year dimension: every year from the first to the last observation.';
COMMENT ON COLUMN analytics.bi_dim_year.year IS 'Calendar year; key for relationships.';
COMMENT ON COLUMN analytics.bi_dim_year.has_annual_data IS
    'At least one complete-year value exists in v_annual_summary (false for the current '
    'partial year).';
COMMENT ON COLUMN analytics.bi_dim_year.is_latest_annual_year IS
    'The most recent year with complete-year data for any indicator.';
