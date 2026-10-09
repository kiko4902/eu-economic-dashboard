-- Map the staged raw rows of indicator :indicator_code to dimension keys and decide which ones
-- are loaded. Each row gets at most one skip_reason (first matching rule wins):
--   null_value        no OBS_VALUE (fact value is NOT NULL)
--   out_of_scope      period outside warehouse.dim_time (before the project start year)
--   outside_validity  year outside dim_indicator.valid_from_year / valid_to_year
-- Unknown geo, unknown flag and a period of the wrong frequency are not skip reasons: they leave
-- country_key / flag_key NULL or frequencies different, and check_mapping.sql fails the run.
-- An unparseable period raises an error in warehouse.period_start_date().
CREATE TEMP TABLE stg_observation ON COMMIT DROP AS
WITH indicator AS (
    SELECT indicator_key, frequency, valid_from_year, valid_to_year
    FROM warehouse.dim_indicator
    WHERE indicator_code = :indicator_code
),
parsed AS (
    SELECT s.*,
           warehouse.period_start_date(s.time_period) AS period_date,
           warehouse.period_frequency(s.time_period)  AS period_frequency,
           warehouse.normalize_flag(s.obs_flag)       AS flag_code
    FROM stg_source AS s
)
SELECT p.geo,
       p.time_period,
       p.obs_value,
       p.obs_flag,
       p.flag_code,
       p.period_frequency,
       i.indicator_key,
       i.frequency,
       c.country_key,
       t.time_key,
       f.flag_key,
       CASE
           WHEN p.obs_value IS NULL THEN 'null_value'
           WHEN t.time_key IS NULL THEN 'out_of_scope'
           WHEN extract(year FROM p.period_date) < i.valid_from_year
             OR extract(year FROM p.period_date) > i.valid_to_year THEN 'outside_validity'
       END AS skip_reason
FROM parsed AS p
CROSS JOIN indicator AS i
LEFT JOIN warehouse.dim_country AS c ON c.country_code = p.geo
LEFT JOIN warehouse.dim_time AS t ON t.period_date = p.period_date
LEFT JOIN warehouse.dim_flag AS f ON f.flag_code = p.flag_code;
