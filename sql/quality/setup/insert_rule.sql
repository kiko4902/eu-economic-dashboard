-- One row of seeds/quality_rules.csv (values as text; empty = NULL).
INSERT INTO qc_rule (indicator_code, min_value, max_value, max_lag_months)
VALUES (:indicator_code,
        CAST(:min_value AS numeric),
        CAST(:max_value AS numeric),
        CAST(NULLIF(:max_lag_months, '') AS integer));
