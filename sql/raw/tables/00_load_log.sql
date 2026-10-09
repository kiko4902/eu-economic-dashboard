-- One row per dataset per extract run.
CREATE TABLE IF NOT EXISTS raw.load_log (
    load_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset       text        NOT NULL,
    rows_loaded   integer,
    started_at    timestamptz NOT NULL DEFAULT now(),
    finished_at   timestamptz,
    status        text        NOT NULL CHECK (status IN ('running', 'success', 'failed')),
    error_message text
);
