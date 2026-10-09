-- Fact rows per indicator (0 for indicators without rows), for the reconciliation check.
SELECT i.indicator_code, count(f.indicator_key) AS fact_rows
FROM warehouse.dim_indicator AS i
LEFT JOIN warehouse.fact_observation AS f ON f.indicator_key = i.indicator_key
GROUP BY i.indicator_code;
