-- Eurostat observation flags (official OBS_FLAG codelist). Seeded from seeds/dim_flag.csv.
CREATE TABLE IF NOT EXISTS warehouse.dim_flag (
    flag_key       smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    flag_code      text     NOT NULL UNIQUE CHECK (flag_code ~ '^[a-z]*$'),
    description    text     NOT NULL,
    is_break       boolean  NOT NULL GENERATED ALWAYS AS (strpos(flag_code, 'b') > 0) STORED,
    is_estimated   boolean  NOT NULL GENERATED ALWAYS AS (strpos(flag_code, 'e') > 0) STORED,
    is_provisional boolean  NOT NULL GENERATED ALWAYS AS (strpos(flag_code, 'p') > 0) STORED
);

COMMENT ON TABLE warehouse.dim_flag IS
    'Observation flag dimension: Eurostat OBS_FLAG codes incl. combinations, plus an empty '
    'code for "no flag".';
COMMENT ON COLUMN warehouse.dim_flag.flag_key IS 'Surrogate key.';
COMMENT ON COLUMN warehouse.dim_flag.flag_code IS
    'Eurostat flag code, e.g. p or bp; empty string = no flag.';
COMMENT ON COLUMN warehouse.dim_flag.description IS 'Official Eurostat description.';
COMMENT ON COLUMN warehouse.dim_flag.is_break IS 'Flag contains b (break in time series).';
COMMENT ON COLUMN warehouse.dim_flag.is_estimated IS 'Flag contains e (estimated).';
COMMENT ON COLUMN warehouse.dim_flag.is_provisional IS 'Flag contains p (provisional).';
