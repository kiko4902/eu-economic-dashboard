-- Flat, human-readable join of the fact table with all dimensions. Main Power BI source.
CREATE OR REPLACE VIEW analytics.v_observations AS
SELECT c.country_code,
       c.country_name,
       c.iso_alpha2,
       c.region,
       c.is_eu_member,
       c.is_aggregate,
       c.euro_adoption_year,
       coalesce(t.year >= c.euro_adoption_year, false) AS is_euro_area_member,
       i.indicator_code,
       i.name                                          AS indicator_name,
       i.unit,
       i.frequency,
       t.period_date,
       t.year,
       t.quarter,
       t.month,
       CASE i.frequency
           WHEN 'A' THEN t.year::text
           WHEN 'Q' THEN t.quarter_label
           ELSE t.period_label
       END                                             AS period_label,
       f.value,
       fl.flag_code,
       fl.description                                  AS flag_description,
       fl.is_provisional,
       fl.is_estimated,
       fl.is_break
FROM warehouse.fact_observation AS f
JOIN warehouse.dim_country AS c ON c.country_key = f.country_key
JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
JOIN warehouse.dim_indicator AS i ON i.indicator_key = f.indicator_key
JOIN warehouse.dim_flag AS fl ON fl.flag_key = f.flag_key;

COMMENT ON VIEW analytics.v_observations IS
    'Every observation (monthly, quarterly, annual) with country, period, indicator and flag '
    'attributes. Main Power BI source.';
COMMENT ON COLUMN analytics.v_observations.is_euro_area_member IS
    'Country used the euro in this year (year >= euro_adoption_year).';
COMMENT ON COLUMN analytics.v_observations.period_date IS 'First day of the period.';
COMMENT ON COLUMN analytics.v_observations.period_label IS
    'Period as Eurostat writes it: 2024 (annual), 2024-Q1 (quarterly), 2024-01 (monthly).';
COMMENT ON COLUMN analytics.v_observations.value IS 'Observed value in the indicator''s unit.';
COMMENT ON COLUMN analytics.v_observations.flag_code IS
    'Eurostat observation flag; empty = no flag.';
