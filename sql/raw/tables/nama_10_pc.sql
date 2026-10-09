-- GDP and main components per capita, annual (Eurostat nama_10_pc).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.nama_10_pc (
    freq         text    NOT NULL,
    unit         text    NOT NULL,
    na_item      text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, unit, na_item, geo, time_period)
);
