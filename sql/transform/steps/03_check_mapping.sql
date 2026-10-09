-- Staged rows that cannot be mapped. Any row returned here fails the indicator's transform:
-- unknown values are never dropped silently.
SELECT 'unknown geo code' AS problem, geo AS value, count(*) AS row_count
FROM stg_observation
WHERE country_key IS NULL
GROUP BY geo
UNION ALL
SELECT 'unknown flag', coalesce(obs_flag, 'NULL'), count(*)
FROM stg_observation
WHERE flag_key IS NULL
GROUP BY obs_flag
UNION ALL
SELECT 'period frequency ' || period_frequency || ' differs from indicator frequency '
           || frequency,
       min(time_period),
       count(*)
FROM stg_observation
WHERE period_frequency <> frequency
GROUP BY period_frequency, frequency
ORDER BY problem, value;
