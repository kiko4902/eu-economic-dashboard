-- Indicators loaded into the fact table. Seeded from seeds/dim_indicator.csv.
CREATE TABLE IF NOT EXISTS warehouse.dim_indicator (
    indicator_key   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    indicator_code  text     NOT NULL UNIQUE CHECK (indicator_code ~ '^[A-Z][A-Z0-9_]*$'),
    name            text     NOT NULL,
    unit            text     NOT NULL,
    frequency       char(1)  NOT NULL CHECK (frequency IN ('A', 'Q', 'M')),
    source_dataset  text     NOT NULL,
    source_filters  text     NOT NULL,
    description     text     NOT NULL,
    notes           text,
    valid_from_year smallint CHECK (valid_from_year BETWEEN 1990 AND 2100),
    valid_to_year   smallint CHECK (valid_to_year BETWEEN 1990 AND 2100),
    CONSTRAINT dim_indicator_valid_range CHECK (valid_from_year <= valid_to_year),
    -- Target of the composite FK that keeps fact_observation.frequency consistent.
    CONSTRAINT dim_indicator_key_frequency_unique UNIQUE (indicator_key, frequency)
);

COMMENT ON TABLE warehouse.dim_indicator IS
    'Indicator dimension: one row per economic indicator (our own codes).';
COMMENT ON COLUMN warehouse.dim_indicator.indicator_key IS 'Surrogate key.';
COMMENT ON COLUMN warehouse.dim_indicator.indicator_code IS
    'Our short code, e.g. HICP_ANNUAL_RATE; natural key.';
COMMENT ON COLUMN warehouse.dim_indicator.name IS 'Display name.';
COMMENT ON COLUMN warehouse.dim_indicator.unit IS 'Unit of the value, e.g. EUR, %, index.';
COMMENT ON COLUMN warehouse.dim_indicator.frequency IS 'A = annual, Q = quarterly, M = monthly.';
COMMENT ON COLUMN warehouse.dim_indicator.source_dataset IS
    'Eurostat dataset code (also the raw table name).';
COMMENT ON COLUMN warehouse.dim_indicator.source_filters IS
    'Eurostat dimension codes selecting this indicator from the dataset.';
COMMENT ON COLUMN warehouse.dim_indicator.description IS 'What the indicator measures.';
COMMENT ON COLUMN warehouse.dim_indicator.notes IS 'Caveats: series breaks, known gaps, cut-offs.';
COMMENT ON COLUMN warehouse.dim_indicator.valid_from_year IS
    'First year loaded into the fact table; NULL = from the project start (2010).';
COMMENT ON COLUMN warehouse.dim_indicator.valid_to_year IS
    'Last year loaded into the fact table (2023 for NET_EARNINGS); NULL = up to the latest period.';
