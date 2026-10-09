-- NET_EARNINGS: annual net earnings, single person without children at 100% of the average
-- wage. Raw holds 2010-2025; the 2023 cut-off (dim_indicator.valid_to_year) is applied by the
-- shared classify step, so the years after the 2024 break are counted as outside_validity.
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.earn_nt_net
WHERE freq = 'A'
  AND currency = 'EUR'
  AND estruct = 'NET'
  AND ecase = 'P1_NCH_AW100';
