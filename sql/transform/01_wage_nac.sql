-- WAGE_NAC: average full-time adjusted salary in national currency (basis for wage growth).
-- Selects the indicator's raw rows into the staging table; the shared steps in steps/ map them
-- to dimension keys and load warehouse.fact_observation (see src/pipeline/transform.py).
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.nama_10_fte
WHERE freq = 'A'
  AND unit = 'NAC';
