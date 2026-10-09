-- Results of the latest data quality run, for the Power BI data quality page. Power BI reads
-- them through this view; powerbi_reader has no access to the quality schema itself.
CREATE OR REPLACE VIEW analytics.v_quality_latest AS
WITH latest AS (
    SELECT *
    FROM quality.check_run
    ORDER BY run_id DESC
    LIMIT 1
)
SELECT l.run_id,
       l.started_at                                      AS run_started_at,
       l.finished_at                                     AS run_finished_at,
       l.status                                          AS run_status,
       r.check_name,
       r.severity,
       r.status,
       r.subject,
       CASE WHEN r.subject IN (SELECT indicator_code FROM warehouse.dim_indicator)
            THEN 'indicator'
            ELSE 'dataset'
       END                                               AS subject_type,
       r.issue_count,
       r.message,
       CASE r.check_name
           WHEN 'load_status' THEN 'Latest Eurostat extract succeeded'
           WHEN 'reconciliation' THEN 'Raw rows = fact rows + rows skipped for a known reason'
           WHEN 'completeness' THEN 'Every country has every indicator from its start year'
           WHEN 'missing_periods' THEN 'No missing periods inside a series'
           WHEN 'value_range' THEN 'Values within plausible ranges'
           WHEN 'known_gaps_current' THEN 'Documented known gaps still match the data'
           WHEN 'freshness' THEN 'Latest period not older than expected'
       END                                               AS check_description
FROM latest AS l
JOIN quality.check_result AS r ON r.run_id = l.run_id;

COMMENT ON VIEW analytics.v_quality_latest IS
    'Results of the latest data quality run (quality.check_run / check_result): one row per '
    'check and subject.';
COMMENT ON COLUMN analytics.v_quality_latest.run_status IS
    'passed, passed_with_warnings or failed (any error-severity failure).';
COMMENT ON COLUMN analytics.v_quality_latest.severity IS
    'error: a failure fails the pipeline; warning: only reported.';
COMMENT ON COLUMN analytics.v_quality_latest.status IS 'pass, fail (error) or warn (warning).';
COMMENT ON COLUMN analytics.v_quality_latest.subject IS 'Indicator code or Eurostat dataset code.';
COMMENT ON COLUMN analytics.v_quality_latest.message IS 'First issues found, or NULL if none.';
