UPDATE raw.load_log
SET finished_at   = now(),
    status        = :status,
    rows_loaded   = :rows_loaded,
    error_message = :error_message
WHERE load_id = :load_id;
