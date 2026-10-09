-- Average full-time adjusted salary per employee, annual (Eurostat nama_10_fte).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.nama_10_fte (
    freq         text    NOT NULL,
    unit         text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, unit, geo, time_period)
);
