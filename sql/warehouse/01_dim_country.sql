-- Countries in scope: EU-27 member states + the EU27_2020 aggregate.
-- Seeded from seeds/dim_country.csv.
CREATE TABLE IF NOT EXISTS warehouse.dim_country (
    country_key        smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_code       text     NOT NULL UNIQUE CHECK (country_code ~ '^[A-Z][A-Z0-9_]*$'),
    country_name       text     NOT NULL,
    iso_alpha2         char(2)  UNIQUE CHECK (iso_alpha2 ~ '^[A-Z]{2}$'),
    is_eu_member       boolean  NOT NULL,
    euro_adoption_year smallint CHECK (euro_adoption_year BETWEEN 1999 AND 2100),
    region             text     CHECK (region IN ('Northern Europe', 'Western Europe',
                                                  'Southern Europe', 'Eastern Europe')),
    is_aggregate       boolean  NOT NULL,
    -- An aggregate has no region, ISO code, membership or euro year; a country has region + ISO.
    CONSTRAINT dim_country_aggregate_consistent CHECK (
        (is_aggregate AND region IS NULL AND iso_alpha2 IS NULL AND NOT is_eu_member
                      AND euro_adoption_year IS NULL)
        OR (NOT is_aggregate AND region IS NOT NULL AND iso_alpha2 IS NOT NULL)
    )
);

COMMENT ON TABLE warehouse.dim_country IS
    'Country dimension: EU-27 member states and the EU27_2020 aggregate.';
COMMENT ON COLUMN warehouse.dim_country.country_key IS 'Surrogate key.';
COMMENT ON COLUMN warehouse.dim_country.country_code IS
    'Eurostat geo code (e.g. HR, EL, EU27_2020); natural key.';
COMMENT ON COLUMN warehouse.dim_country.country_name IS 'English name.';
COMMENT ON COLUMN warehouse.dim_country.iso_alpha2 IS
    'ISO 3166-1 alpha-2 code for maps (Greece is GR, Eurostat uses EL); NULL for aggregates.';
COMMENT ON COLUMN warehouse.dim_country.is_eu_member IS
    'True for current EU member states; false for aggregates.';
COMMENT ON COLUMN warehouse.dim_country.euro_adoption_year IS
    'Year the country adopted the euro (source: ECB); NULL if not in the euro area.';
COMMENT ON COLUMN warehouse.dim_country.region IS
    'UN M49 geoscheme sub-region (Cyprus mapped to Southern Europe, see docs/data_sources.md); '
    'NULL for aggregates.';
COMMENT ON COLUMN warehouse.dim_country.is_aggregate IS 'True for aggregates such as EU27_2020.';
