-- Datasets whose latest extract did not succeed (or that were never extracted).
WITH datasets AS (
    SELECT unnest(CAST(:datasets AS text[])) AS dataset
),
latest AS (
    SELECT DISTINCT ON (dataset) dataset, status, error_message, started_at
    FROM raw.load_log
    ORDER BY dataset, load_id DESC
)
SELECT d.dataset AS subject,
       CASE WHEN l.dataset IS NULL THEN 'never extracted (no row in raw.load_log)'
            ELSE format('latest extract (%s) has status %s: %s',
                        to_char(l.started_at, 'YYYY-MM-DD HH24:MI'), l.status,
                        coalesce(l.error_message, 'no error message'))
       END AS detail
FROM datasets AS d
LEFT JOIN latest AS l ON l.dataset = d.dataset
WHERE l.status IS DISTINCT FROM 'success';
