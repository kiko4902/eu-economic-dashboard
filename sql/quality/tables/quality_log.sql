-- Results of the data quality checks (src/pipeline/quality.py), one run per `make quality`.
CREATE SCHEMA IF NOT EXISTS quality;

CREATE TABLE IF NOT EXISTS quality.check_run (
    run_id      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at  timestamptz NOT NULL,
    finished_at timestamptz NOT NULL DEFAULT now(),
    status      text        NOT NULL CHECK (status IN ('passed', 'passed_with_warnings', 'failed')),
    errors      integer     NOT NULL CHECK (errors >= 0),
    warnings    integer     NOT NULL CHECK (warnings >= 0)
);

CREATE TABLE IF NOT EXISTS quality.check_result (
    run_id      bigint  NOT NULL REFERENCES quality.check_run (run_id),
    check_name  text    NOT NULL,
    subject     text    NOT NULL,
    severity    text    NOT NULL CHECK (severity IN ('error', 'warning')),
    status      text    NOT NULL CHECK (status IN ('pass', 'fail', 'warn')),
    issue_count integer NOT NULL CHECK (issue_count >= 0),
    message     text,
    PRIMARY KEY (run_id, check_name, subject)
);

-- The known gaps (seeds/known_gaps.csv) each run used, so reports can show the documented
-- exceptions that applied to that run's results.
CREATE TABLE IF NOT EXISTS quality.check_known_gap (
    run_id         bigint NOT NULL REFERENCES quality.check_run (run_id),
    indicator_code text   NOT NULL,
    country_code   text   NOT NULL,
    gap_type       text   NOT NULL CHECK (gap_type IN ('no_series', 'missing_periods')),
    from_period    text,
    to_period      text,
    reason         text   NOT NULL
);

CREATE INDEX IF NOT EXISTS check_known_gap_run_id_idx ON quality.check_known_gap (run_id);

COMMENT ON SCHEMA quality IS 'Data quality check results.';
COMMENT ON TABLE quality.check_run IS 'One row per quality run (make quality / make pipeline).';
COMMENT ON COLUMN quality.check_run.status IS
    'failed if any error-severity check failed; warnings never fail a run.';
COMMENT ON COLUMN quality.check_run.errors IS 'Number of failed error-severity results.';
COMMENT ON COLUMN quality.check_run.warnings IS 'Number of warning results.';
COMMENT ON TABLE quality.check_result IS
    'One row per check and subject (indicator or dataset) per run.';
COMMENT ON COLUMN quality.check_result.subject IS 'Indicator code or dataset code checked.';
COMMENT ON COLUMN quality.check_result.severity IS
    'error: a failure fails the pipeline; warning: only logged.';
COMMENT ON COLUMN quality.check_result.status IS
    'pass; fail (error severity) or warn (warning severity) when issues were found.';
COMMENT ON COLUMN quality.check_result.issue_count IS 'Number of issues found.';
COMMENT ON COLUMN quality.check_result.message IS 'First issues found (examples), or NULL.';
COMMENT ON TABLE quality.check_known_gap IS
    'Known gaps (seeds/known_gaps.csv) in force for each run; append-only like the results.';
COMMENT ON COLUMN quality.check_known_gap.gap_type IS
    'no_series: country has no data at all; missing_periods: from_period..to_period may be missing.';
