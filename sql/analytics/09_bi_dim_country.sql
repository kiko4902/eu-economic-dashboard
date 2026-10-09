-- Country dimension for Power BI: one row per country_code (27 member states + EU27_2020).
-- Relates one-to-many to every analytics view with a country_code column.
CREATE OR REPLACE VIEW analytics.bi_dim_country AS
SELECT country_code,
       country_name,
       CASE country_code
           WHEN 'EU27_2020' THEN 'EU27'
           ELSE country_name
       END                                                       AS country_short_name,
       iso_alpha2,
       region,
       is_eu_member,
       is_aggregate,
       euro_adoption_year,
       CASE country_code
           WHEN 'HR' THEN 'Croatia'
           WHEN 'EU27_2020' THEN 'EU average'
           ELSE 'Other member states'
       END                                                       AS comparison_group,
       -- Same colours as powerbi/theme.json, for conditional formatting by field value.
       CASE country_code
           WHEN 'HR' THEN '#C8102E'
           WHEN 'EU27_2020' THEN '#1F4E9E'
           ELSE '#9AA3AD'
       END                                                       AS highlight_colour,
       -- Croatia first, the EU aggregate second, then the member states by name.
       CASE country_code
           WHEN 'HR' THEN 1
           WHEN 'EU27_2020' THEN 2
           ELSE 2 + row_number() OVER (
                    PARTITION BY country_code IN ('HR', 'EU27_2020')
                    ORDER BY country_name
                )
       END                                                       AS sort_order
FROM warehouse.dim_country;

COMMENT ON VIEW analytics.bi_dim_country IS
    'Power BI country dimension: one row per country_code (27 member states + EU27_2020), '
    'with a sort order that puts Croatia and the EU aggregate first.';
COMMENT ON COLUMN analytics.bi_dim_country.country_code IS
    'Eurostat geo code (EL = Greece); key for relationships to the analytics views.';
COMMENT ON COLUMN analytics.bi_dim_country.country_short_name IS
    'Name for axis labels: EU27 instead of the long aggregate name.';
COMMENT ON COLUMN analytics.bi_dim_country.iso_alpha2 IS
    'ISO 3166-1 alpha-2 code for map visuals (GR for Greece); NULL for EU27_2020.';
COMMENT ON COLUMN analytics.bi_dim_country.comparison_group IS
    'Croatia, EU average or Other member states, for legends and colours.';
COMMENT ON COLUMN analytics.bi_dim_country.highlight_colour IS
    'Hex colour matching powerbi/theme.json: Croatia red, EU blue, others grey.';
COMMENT ON COLUMN analytics.bi_dim_country.sort_order IS
    '1 = Croatia, 2 = EU27_2020, then member states alphabetically; use as Sort by column.';
