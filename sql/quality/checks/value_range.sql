-- Values outside the plausible range of their indicator (seeds/quality_rules.csv): every fact
-- observation, plus the derived annual inflation from analytics.v_annual_summary.
WITH observed AS (
    SELECT i.indicator_code,
           c.country_code,
           CASE i.frequency WHEN 'A' THEN to_char(t.period_date, 'YYYY')
                            WHEN 'Q' THEN t.quarter_label
                            ELSE t.period_label END AS period_label,
           f.value
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = f.indicator_key
    JOIN warehouse.dim_country AS c ON c.country_key = f.country_key
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
    UNION ALL
    SELECT indicator_code, country_code, CAST(year AS text), value
    FROM analytics.v_annual_summary
    WHERE indicator_code = 'HICP_INFLATION'
)
SELECT o.indicator_code AS subject,
       format('%s %s: %s outside [%s, %s]', o.country_code, o.period_label,
              round(o.value, 2), r.min_value, r.max_value) AS detail
FROM observed AS o
JOIN qc_rule AS r ON r.indicator_code = o.indicator_code
WHERE o.value < r.min_value
   OR o.value > r.max_value
ORDER BY subject, o.country_code, o.period_label;
