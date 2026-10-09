INSERT INTO raw.load_log (dataset, status)
VALUES (:dataset, 'running')
RETURNING load_id;
