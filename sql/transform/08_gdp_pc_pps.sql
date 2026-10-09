-- GDP_PC_PPS: GDP per inhabitant in PPS (EU27_2020 basis), annual.
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.nama_10_pc
WHERE freq = 'A'
  AND unit = 'CP_PPS_EU27_2020_HAB'
  AND na_item = 'B1GQ';
