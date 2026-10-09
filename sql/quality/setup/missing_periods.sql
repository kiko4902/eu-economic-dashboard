-- Every period missing from a country's series, from the indicator's start (valid_from_year or
-- the project start year) to the series' last period:
--   leading  - before the series' first observation (a late start)
--   internal - between its first and last observation (a hole)
-- is_known_gap marks periods covered by a missing_periods known gap.
CREATE TEMP TABLE qc_missing_period ON COMMIT DROP AS
WITH series AS (
    SELECT f.indicator_key,
           f.country_key,
           min(t.period_date) AS first_period,
           max(t.period_date) AS last_period
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
    GROUP BY f.indicator_key, f.country_key
),
expected AS (
    SELECT s.*,
           i.indicator_code,
           i.frequency,
           c.country_code,
           CAST(p AS date) AS period_date
    FROM series AS s
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = s.indicator_key
    JOIN warehouse.dim_country AS c ON c.country_key = s.country_key
    CROSS JOIN LATERAL generate_series(
        CAST(make_date(coalesce(i.valid_from_year, CAST(:start_year AS integer)), 1, 1)
             AS timestamp),
        CAST(s.last_period AS timestamp),
        CASE i.frequency WHEN 'A' THEN INTERVAL '1 year'
                         WHEN 'Q' THEN INTERVAL '3 months'
                         ELSE INTERVAL '1 month' END
    ) AS p
)
SELECT e.indicator_code,
       e.country_code,
       e.period_date,
       CASE e.frequency WHEN 'A' THEN to_char(e.period_date, 'YYYY')
                        WHEN 'Q' THEN to_char(e.period_date, 'YYYY-"Q"Q')
                        ELSE to_char(e.period_date, 'YYYY-MM') END    AS period_label,
       CASE WHEN e.period_date < e.first_period THEN 'leading'
            ELSE 'internal' END                                       AS position,
       EXISTS (
           SELECT 1
           FROM qc_known_gap AS g
           WHERE g.indicator_code = e.indicator_code
             AND g.country_code = e.country_code
             AND g.gap_type = 'missing_periods'
             AND e.period_date BETWEEN g.from_date AND g.to_date
       )                                                              AS is_known_gap
FROM expected AS e
WHERE NOT EXISTS (
    SELECT 1
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
    WHERE f.indicator_key = e.indicator_key
      AND f.country_key = e.country_key
      AND t.period_date = e.period_date
);
