-- HICP_INDEX: all-items HICP, monthly index 2025 = 100 (basis for annual inflation).
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.prc_hicp_minr
WHERE freq = 'M'
  AND unit = 'I25'
  AND coicop18 = 'TOTAL';
