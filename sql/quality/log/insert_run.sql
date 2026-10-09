-- Record one quality run; returns its run_id.
INSERT INTO quality.check_run (started_at, status, errors, warnings)
VALUES (:started_at, :status, :errors, :warnings)
RETURNING run_id;
