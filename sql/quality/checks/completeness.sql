-- Every EU-27 country + EU27_2020 has a series for every indicator, starting at the indicator's
-- start (valid_from_year or the project start), except documented known gaps
-- (seeds/known_gaps.csv: no_series, or missing_periods covering the late start).
WITH missing_series AS (
    SELECT i.indicator_code AS subject,
           format('%s: no data', c.country_code) AS detail
    FROM warehouse.dim_indicator AS i
    CROSS JOIN warehouse.dim_country AS c
    WHERE NOT EXISTS (
              SELECT 1
              FROM warehouse.fact_observation AS f
              WHERE f.indicator_key = i.indicator_key
                AND f.country_key = c.country_key
          )
      AND NOT EXISTS (
              SELECT 1
              FROM qc_known_gap AS g
              WHERE g.indicator_code = i.indicator_code
                AND g.country_code = c.country_code
                AND g.gap_type = 'no_series'
          )
),
late_start AS (
    SELECT indicator_code AS subject,
           format('%s: starts late, missing %s to %s (%s periods)', country_code,
                  min(period_label), max(period_label), count(*)) AS detail
    FROM qc_missing_period
    WHERE position = 'leading'
      AND NOT is_known_gap
    GROUP BY indicator_code, country_code
)
SELECT subject, detail FROM missing_series
UNION ALL
SELECT subject, detail FROM late_start
ORDER BY subject, detail;
