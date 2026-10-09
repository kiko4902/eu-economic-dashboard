-- All indicators at annual grain, complete years only.
--   - annual indicators (wages, net earnings, GDP): as reported
--   - monthly / quarterly indicators (HICP index, unemployment, house prices): annual average,
--     only for years with all 12 months / 4 quarters; partial years are left out, never averaged
--   - HICP_INFLATION (derived): annual average HICP index / previous year's annual average - 1,
--     Eurostat's method for the annual average rate; needs two complete years, so it starts in
--     2011 (the warehouse starts in 2010)
-- HICP_ANNUAL_RATE is not summarised: an average of 12 monthly annual rates is only an
-- approximation of annual inflation, and HICP_INFLATION is the exact figure.
CREATE OR REPLACE VIEW analytics.v_annual_summary AS
WITH yearly AS (
    SELECT f.country_key,
           f.indicator_key,
           i.frequency,
           t.year,
           CASE WHEN i.frequency = 'A' THEN max(f.value) ELSE avg(f.value) END AS value,
           count(*)                                                        AS observation_count,
           bool_or(fl.is_provisional)                                      AS has_provisional,
           bool_or(fl.is_estimated)                                        AS has_estimated,
           bool_or(fl.is_break)                                            AS has_break
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = f.indicator_key
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
    JOIN warehouse.dim_flag AS fl ON fl.flag_key = f.flag_key
    WHERE i.indicator_code <> 'HICP_ANNUAL_RATE'
    GROUP BY f.country_key, f.indicator_key, i.frequency, t.year
),
complete_years AS (
    SELECT *
    FROM yearly
    WHERE observation_count = CASE frequency WHEN 'A' THEN 1 WHEN 'Q' THEN 4 WHEN 'M' THEN 12 END
),
reported AS (
    SELECT y.country_key,
           i.indicator_code,
           i.name AS indicator_name,
           i.unit,
           y.year,
           y.value,
           CASE y.frequency
               WHEN 'A' THEN 'annual value as reported'
               WHEN 'Q' THEN 'average of 4 quarters'
               ELSE 'average of 12 months'
           END    AS aggregation_method,
           y.observation_count,
           y.has_provisional,
           y.has_estimated,
           y.has_break
    FROM complete_years AS y
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = y.indicator_key
),
hicp_index AS (
    SELECT y.*,
           lag(y.year) OVER w              AS previous_year,
           lag(y.value) OVER w             AS previous_value,
           lag(y.observation_count) OVER w AS previous_observation_count,
           lag(y.has_provisional) OVER w   AS previous_has_provisional,
           lag(y.has_estimated) OVER w     AS previous_has_estimated,
           lag(y.has_break) OVER w         AS previous_has_break
    FROM complete_years AS y
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = y.indicator_key
    WHERE i.indicator_code = 'HICP_INDEX'
    WINDOW w AS (PARTITION BY y.country_key ORDER BY y.year)
),
inflation AS (
    SELECT country_key,
           'HICP_INFLATION'                                         AS indicator_code,
           'Inflation (HICP, annual average)'                       AS indicator_name,
           '% change on previous year'                              AS unit,
           year,
           (value / previous_value - 1) * 100                       AS value,
           'annual average index / previous year''s average - 1'    AS aggregation_method,
           observation_count + previous_observation_count           AS observation_count,
           has_provisional OR previous_has_provisional              AS has_provisional,
           has_estimated OR previous_has_estimated                  AS has_estimated,
           has_break OR previous_has_break                          AS has_break
    FROM hicp_index
    WHERE previous_year = year - 1  -- both years complete
),
combined AS (
    SELECT * FROM reported
    UNION ALL
    SELECT * FROM inflation
)
SELECT c.country_code,
       c.country_name,
       c.region,
       c.is_eu_member,
       c.is_aggregate,
       a.indicator_code,
       a.indicator_name,
       a.unit,
       a.year,
       a.value,
       a.aggregation_method,
       a.observation_count,
       a.has_provisional,
       a.has_estimated,
       a.has_break
FROM combined AS a
JOIN warehouse.dim_country AS c ON c.country_key = a.country_key;

COMMENT ON VIEW analytics.v_annual_summary IS
    'All indicators per country and year, complete years only (12 months / 4 quarters / 1 '
    'annual value; partial years are excluded). Monthly and quarterly indicators are annual '
    'averages; HICP_INFLATION is derived from the HICP index (annual average index ratio).';
COMMENT ON COLUMN analytics.v_annual_summary.indicator_code IS
    'Warehouse indicator code, or HICP_INFLATION (derived annual inflation, %).';
COMMENT ON COLUMN analytics.v_annual_summary.value IS
    'Annual value in the unit column: as reported, annual average, or derived inflation (%).';
COMMENT ON COLUMN analytics.v_annual_summary.aggregation_method IS
    'How the annual value was built from the observations.';
COMMENT ON COLUMN analytics.v_annual_summary.observation_count IS
    'Observations used: 1 (annual), 4 (quarterly), 12 (monthly); 24 for HICP_INFLATION '
    '(this and the previous year).';
COMMENT ON COLUMN analytics.v_annual_summary.has_provisional IS
    'At least one underlying observation is provisional (flag p).';
COMMENT ON COLUMN analytics.v_annual_summary.has_estimated IS
    'At least one underlying observation is estimated (flag e).';
COMMENT ON COLUMN analytics.v_annual_summary.has_break IS
    'At least one underlying observation has a break in series (flag b).';
