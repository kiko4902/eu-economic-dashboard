-- Annual net earnings (Eurostat earn_nt_net).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.earn_nt_net (
    freq         text    NOT NULL,
    currency     text    NOT NULL,
    estruct      text    NOT NULL,
    ecase        text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, currency, estruct, ecase, geo, time_period)
);
