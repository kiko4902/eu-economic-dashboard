-- One known gap (seeds/known_gaps.csv row) in force for a quality run.
INSERT INTO quality.check_known_gap
    (run_id, indicator_code, country_code, gap_type, from_period, to_period, reason)
VALUES (:run_id, :indicator_code, :country_code, :gap_type,
        NULLIF(:from_period, ''), NULLIF(:to_period, ''), :reason);
