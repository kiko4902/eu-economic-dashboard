-- Rows read for the indicator and how many are skipped, per reason.
SELECT count(*)                                                  AS rows_read,
       count(*) FILTER (WHERE skip_reason IS NULL)               AS rows_valid,
       count(*) FILTER (WHERE skip_reason = 'null_value')        AS null_value,
       count(*) FILTER (WHERE skip_reason = 'out_of_scope')      AS out_of_scope,
       count(*) FILTER (WHERE skip_reason = 'outside_validity')  AS outside_validity
FROM stg_observation;
