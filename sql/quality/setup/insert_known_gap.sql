-- One row of seeds/known_gaps.csv; periods are Eurostat labels (2013, 2024-Q1, 2024-01).
INSERT INTO qc_known_gap (indicator_code, country_code, gap_type, from_date, to_date, reason)
VALUES (:indicator_code,
        :country_code,
        :gap_type,
        warehouse.period_start_date(NULLIF(:from_period, '')),
        warehouse.period_start_date(NULLIF(:to_period, '')),
        :reason);
