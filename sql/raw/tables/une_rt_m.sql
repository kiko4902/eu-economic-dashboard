-- Unemployment rate, monthly (Eurostat une_rt_m).
-- Long format, exactly as received from the Eurostat SDMX-CSV API (filtered to scope).
CREATE TABLE IF NOT EXISTS raw.une_rt_m (
    freq         text    NOT NULL,
    s_adj        text    NOT NULL,
    age          text    NOT NULL,
    unit         text    NOT NULL,
    sex          text    NOT NULL,
    geo          text    NOT NULL,
    time_period  text    NOT NULL,
    obs_value    numeric,
    obs_flag     text,
    conf_status  text,
    load_id      bigint  NOT NULL REFERENCES raw.load_log (load_id),
    loaded_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (freq, s_adj, age, unit, sex, geo, time_period)
);
