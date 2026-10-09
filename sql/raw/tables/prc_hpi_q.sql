-- House price index, quarterly (Eurostat prc_hpi_q).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.prc_hpi_q (
    freq         text    NOT NULL,
    purchase     text    NOT NULL,
    unit         text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, purchase, unit, geo, time_period)
);
