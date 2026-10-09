-- HICP, ECOICOP ver.2, monthly index (I25) and annual rate of change (RCH_A) (Eurostat prc_hicp_minr).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.prc_hicp_minr (
    freq         text    NOT NULL,
    unit         text    NOT NULL,
    coicop18     text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, unit, coicop18, geo, time_period)
);
