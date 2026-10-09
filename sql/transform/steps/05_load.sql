-- Synchronise warehouse.fact_observation for indicator :indicator_code with the valid staged
-- rows, in one statement:
--   - rows no longer in the source are deleted
--   - new rows are inserted, changed rows (value, flag) are updated
--   - unchanged rows are not touched, so re-running the transform rewrites nothing.
-- Deleted and upserted rows have different keys, so the two data-modifying CTEs do not overlap.
WITH valid AS (
    SELECT country_key, time_key, indicator_key, flag_key, frequency, obs_value AS value
    FROM stg_observation
    WHERE skip_reason IS NULL
),
deleted AS (
    DELETE FROM warehouse.fact_observation AS f
    WHERE f.indicator_key = (
              SELECT indicator_key
              FROM warehouse.dim_indicator
              WHERE indicator_code = :indicator_code
          )
      AND NOT EXISTS (
              SELECT 1
              FROM valid AS v
              WHERE v.country_key = f.country_key
                AND v.time_key = f.time_key
          )
    RETURNING 1
),
upserted AS (
    INSERT INTO warehouse.fact_observation AS f
        (country_key, time_key, indicator_key, flag_key, frequency, value)
    SELECT country_key, time_key, indicator_key, flag_key, frequency, value
    FROM valid
    ON CONFLICT ON CONSTRAINT fact_observation_pk DO UPDATE
        SET flag_key  = excluded.flag_key,
            frequency = excluded.frequency,
            value     = excluded.value
        WHERE (f.flag_key, f.frequency, f.value)
              IS DISTINCT FROM (excluded.flag_key, excluded.frequency, excluded.value)
    RETURNING (f.xmax = 0) AS is_insert  -- xmax = 0: the row version was inserted, not updated
)
SELECT (SELECT count(*) FROM valid)                         AS rows_loaded,
       (SELECT count(*) FROM upserted WHERE is_insert)      AS inserted,
       (SELECT count(*) FROM upserted WHERE NOT is_insert)  AS updated,
       (SELECT count(*) FROM deleted)                       AS deleted;
