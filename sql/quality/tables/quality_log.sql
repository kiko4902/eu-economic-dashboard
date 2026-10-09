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
