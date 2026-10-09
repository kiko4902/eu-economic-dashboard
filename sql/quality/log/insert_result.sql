-- One check result of a quality run.
INSERT INTO quality.check_result
    (run_id, check_name, subject, severity, status, issue_count, message)
VALUES (:run_id, :check_name, :subject, :severity, :status, :issue_count, :message);
