-- Upsert one dim_flag row (parameters are the seed CSV values as text).
-- Unchanged rows are not touched, so re-running the seed is a no-op.
MERGE INTO warehouse.dim_flag AS t
USING (
    SELECT CAST(:flag_code AS text)   AS flag_code,
           CAST(:description AS text) AS description
) AS s
ON t.flag_code = s.flag_code
WHEN MATCHED AND t.description IS DISTINCT FROM s.description THEN
    UPDATE SET description = s.description
WHEN NOT MATCHED THEN
    INSERT (flag_code, description)
    VALUES (s.flag_code, s.description);
