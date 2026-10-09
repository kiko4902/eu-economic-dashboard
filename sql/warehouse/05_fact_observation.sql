-- One value per country, period and indicator. Loaded from the raw tables in Phase 3.
CREATE TABLE IF NOT EXISTS warehouse.fact_observation (
    country_key   smallint NOT NULL REFERENCES warehouse.dim_country (country_key),
    time_key      integer  NOT NULL REFERENCES warehouse.dim_time (time_key),
    indicator_key smallint NOT NULL,
    flag_key      smallint NOT NULL REFERENCES warehouse.dim_flag (flag_key),
    frequency     char(1)  NOT NULL CHECK (frequency IN ('A', 'Q', 'M')),
    value         numeric  NOT NULL,
    CONSTRAINT fact_observation_pk PRIMARY KEY (country_key, time_key, indicator_key),
    -- The fact's frequency must be its indicator's frequency.
    CONSTRAINT fact_observation_indicator_fk FOREIGN KEY (indicator_key, frequency)
        REFERENCES warehouse.dim_indicator (indicator_key, frequency)
);

-- The primary key index already covers country_key; index the other FK columns.
CREATE INDEX IF NOT EXISTS fact_observation_time_key_idx
    ON warehouse.fact_observation (time_key);
CREATE INDEX IF NOT EXISTS fact_observation_indicator_key_idx
    ON warehouse.fact_observation (indicator_key);
CREATE INDEX IF NOT EXISTS fact_observation_flag_key_idx
    ON warehouse.fact_observation (flag_key);

COMMENT ON TABLE warehouse.fact_observation IS
    'Fact table: observed indicator values at monthly, quarterly or annual grain.';
COMMENT ON COLUMN warehouse.fact_observation.country_key IS 'FK to dim_country.';
COMMENT ON COLUMN warehouse.fact_observation.time_key IS
    'FK to dim_time: first month of the observation period.';
COMMENT ON COLUMN warehouse.fact_observation.indicator_key IS
    'FK to dim_indicator (together with frequency).';
COMMENT ON COLUMN warehouse.fact_observation.flag_key IS
    'FK to dim_flag; the empty-code row when Eurostat sent no flag.';
COMMENT ON COLUMN warehouse.fact_observation.frequency IS
    'A/Q/M; must equal dim_indicator.frequency (composite FK).';
COMMENT ON COLUMN warehouse.fact_observation.value IS
    'Observation value in the indicator''s unit (Eurostat OBS_VALUE); rows without a value are '
    'not loaded.';
