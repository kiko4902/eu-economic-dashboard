-- HICP_ANNUAL_RATE: all-items HICP, annual rate of change (same month of previous year).
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.prc_hicp_minr
WHERE freq = 'M'
  AND unit = 'RCH_A'
  AND coicop18 = 'TOTAL';
