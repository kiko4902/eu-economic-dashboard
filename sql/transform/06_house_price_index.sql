-- HOUSE_PRICE_INDEX: all dwellings, quarterly index 2015 = 100. Greece is not in the source.
INSERT INTO stg_source (geo, time_period, obs_value, obs_flag)
SELECT geo, time_period, obs_value, obs_flag
FROM raw.prc_hpi_q
WHERE freq = 'Q'
  AND purchase = 'TOTAL'
  AND unit = 'I15_Q';
