-- Upsert one dim_country row (parameters are the seed CSV values as text).
-- Unchanged rows are not touched, so re-running the seed is a no-op.
MERGE INTO warehouse.dim_country AS t
USING (
    SELECT CAST(:country_code AS text)                          AS country_code,
           CAST(:country_name AS text)                          AS country_name,
           CAST(NULLIF(:iso_alpha2, '') AS char(2))             AS iso_alpha2,
           CAST(:is_eu_member AS boolean)                       AS is_eu_member,
           CAST(NULLIF(:euro_adoption_year, '') AS smallint)    AS euro_adoption_year,
           CAST(NULLIF(:region, '') AS text)                    AS region,
           CAST(:is_aggregate AS boolean)                       AS is_aggregate
) AS s
ON t.country_code = s.country_code
WHEN MATCHED AND (t.country_name, t.iso_alpha2, t.is_eu_member, t.euro_adoption_year,
                  t.region, t.is_aggregate)
     IS DISTINCT FROM (s.country_name, s.iso_alpha2, s.is_eu_member, s.euro_adoption_year,
                       s.region, s.is_aggregate) THEN
    UPDATE SET country_name       = s.country_name,
               iso_alpha2         = s.iso_alpha2,
               is_eu_member       = s.is_eu_member,
               euro_adoption_year = s.euro_adoption_year,
               region             = s.region,
               is_aggregate       = s.is_aggregate
WHEN NOT MATCHED THEN
    INSERT (country_code, country_name, iso_alpha2, is_eu_member, euro_adoption_year, region,
            is_aggregate)
    VALUES (s.country_code, s.country_name, s.iso_alpha2, s.is_eu_member, s.euro_adoption_year,
            s.region, s.is_aggregate);
