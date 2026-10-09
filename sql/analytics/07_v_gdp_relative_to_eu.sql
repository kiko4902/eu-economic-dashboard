-- GDP per capita in PPS relative to the EU, EU27_2020 = 100 (Eurostat publishes the same
-- measure as nama_10_pc unit PC_EU27_2020_HAB_MPPS_CP).
CREATE OR REPLACE VIEW analytics.v_gdp_relative_to_eu AS
WITH gdp AS (
    SELECT a.*,
           max(a.value) FILTER (WHERE a.country_code = 'EU27_2020') OVER w AS eu_value,
           bool_or(a.has_provisional) FILTER (WHERE a.country_code = 'EU27_2020') OVER w
                                                                          AS eu_has_provisional,
           bool_or(a.has_estimated) FILTER (WHERE a.country_code = 'EU27_2020') OVER w
                                                                          AS eu_has_estimated,
           bool_or(a.has_break) FILTER (WHERE a.country_code = 'EU27_2020') OVER w
                                                                          AS eu_has_break
    FROM analytics.v_annual_summary AS a
    WHERE a.indicator_code = 'GDP_PC_PPS'
    WINDOW w AS (PARTITION BY a.year)
)
SELECT country_code,
       country_name,
       region,
       is_eu_member,
       year,
       value                                  AS gdp_pc_pps,
       eu_value                               AS eu_gdp_pc_pps,
       value / eu_value * 100                 AS gdp_pc_index_eu27,
       has_provisional OR eu_has_provisional  AS has_provisional,
       has_estimated OR eu_has_estimated      AS has_estimated,
       has_break OR eu_has_break              AS has_break
FROM gdp
WHERE NOT is_aggregate
  AND eu_value IS NOT NULL;

COMMENT ON VIEW analytics.v_gdp_relative_to_eu IS
    'GDP per capita in purchasing power standards per member state, EU27_2020 = 100.';
COMMENT ON COLUMN analytics.v_gdp_relative_to_eu.gdp_pc_pps IS
    'GDP per inhabitant, PPS (EU27_2020 basis).';
COMMENT ON COLUMN analytics.v_gdp_relative_to_eu.eu_gdp_pc_pps IS
    'EU27_2020 GDP per inhabitant, PPS.';
COMMENT ON COLUMN analytics.v_gdp_relative_to_eu.gdp_pc_index_eu27 IS
    'gdp_pc_pps / EU27_2020 value * 100; 77 = 77 % of the EU average.';
