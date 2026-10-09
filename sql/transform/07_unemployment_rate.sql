-- UNEMPLOYMENT_RATE: seasonally adjusted, total, % of the labour force, monthly.
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.une_rt_m
WHERE freq = 'M'
  AND s_adj = 'SA'
  AND age = 'TOTAL'
  AND unit = 'PC_ACT'
  AND sex = 'T';
