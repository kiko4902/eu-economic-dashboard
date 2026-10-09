-- Holes inside a country's series (between its first and last observation), except periods
-- covered by a missing_periods known gap.
SELECT indicator_code AS subject,
       format('%s: missing %s', country_code,
              string_agg(period_label, ', ' ORDER BY period_date)) AS detail
FROM qc_missing_period
WHERE position = 'internal'
  AND NOT is_known_gap
GROUP BY indicator_code, country_code
ORDER BY subject, detail;
