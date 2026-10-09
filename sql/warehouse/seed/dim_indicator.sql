-- Upsert one dim_indicator row (parameters are the seed CSV values as text).
-- Unchanged rows are not touched, so re-running the seed is a no-op.
MERGE INTO warehouse.dim_indicator AS t
USING (
    SELECT CAST(:indicator_code AS text)                     AS indicator_code,
           CAST(:name AS text)                               AS name,
           CAST(:unit AS text)                               AS unit,
           CAST(:frequency AS char(1))                       AS frequency,
           CAST(:source_dataset AS text)                     AS source_dataset,
           CAST(:source_filters AS text)                     AS source_filters,
           CAST(:description AS text)                        AS description,
           CAST(NULLIF(:notes, '') AS text)                  AS notes,
           CAST(NULLIF(:valid_from_year, '') AS smallint)    AS valid_from_year,
           CAST(NULLIF(:valid_to_year, '') AS smallint)      AS valid_to_year
) AS s
ON t.indicator_code = s.indicator_code
WHEN MATCHED AND (t.name, t.unit, t.frequency, t.source_dataset, t.source_filters,
                  t.description, t.notes, t.valid_from_year, t.valid_to_year)
     IS DISTINCT FROM (s.name, s.unit, s.frequency, s.source_dataset, s.source_filters,
                       s.description, s.notes, s.valid_from_year, s.valid_to_year) THEN
    UPDATE SET name            = s.name,
               unit            = s.unit,
               frequency       = s.frequency,
               source_dataset  = s.source_dataset,
               source_filters  = s.source_filters,
               description     = s.description,
               notes           = s.notes,
               valid_from_year = s.valid_from_year,
               valid_to_year   = s.valid_to_year
WHEN NOT MATCHED THEN
    INSERT (indicator_code, name, unit, frequency, source_dataset, source_filters, description,
            notes, valid_from_year, valid_to_year)
    VALUES (s.indicator_code, s.name, s.unit, s.frequency, s.source_dataset, s.source_filters,
            s.description, s.notes, s.valid_from_year, s.valid_to_year);
