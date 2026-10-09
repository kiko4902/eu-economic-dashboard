-- Known gaps that no longer match the data (the data has appeared): the entry in
-- seeds/known_gaps.csv should be removed or narrowed, otherwise it could hide a future problem.
SELECT g.indicator_code AS subject,
       format('%s: known gap (%s%s) no longer applies; reason was: %s', g.country_code,
              g.gap_type,
              coalesce(' ' || to_char(g.from_date, 'YYYY-MM') || ' to '
                       || to_char(g.to_date, 'YYYY-MM'), ''),
              g.reason) AS detail
FROM qc_known_gap AS g
WHERE (g.gap_type = 'no_series'
       AND EXISTS (
           SELECT 1
           FROM warehouse.fact_observation AS f
           JOIN warehouse.dim_indicator AS i ON i.indicator_key = f.indicator_key
           JOIN warehouse.dim_country AS c ON c.country_key = f.country_key
           WHERE i.indicator_code = g.indicator_code
             AND c.country_code = g.country_code
       ))
   OR (g.gap_type = 'missing_periods'
       AND NOT EXISTS (
           SELECT 1
           FROM qc_missing_period AS m
           WHERE m.indicator_code = g.indicator_code
             AND m.country_code = g.country_code
             AND m.period_date BETWEEN g.from_date AND g.to_date
       ))
ORDER BY subject, detail;
