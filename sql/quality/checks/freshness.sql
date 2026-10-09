-- Indicators whose latest period (over all countries) ended more than max_lag_months before
-- :as_of (seeds/quality_rules.csv). Warning only: Eurostat release dates vary.
WITH latest AS (
    SELECT i.indicator_code,
           max(t.period_date + CASE i.frequency WHEN 'A' THEN INTERVAL '1 year'
                                                WHEN 'Q' THEN INTERVAL '3 months'
                                                ELSE INTERVAL '1 month' END) AS latest_end,
           max(CASE i.frequency WHEN 'A' THEN to_char(t.period_date, 'YYYY')
                                WHEN 'Q' THEN t.quarter_label
                                ELSE t.period_label END)                     AS latest_period
    FROM warehouse.fact_observation AS f
    JOIN warehouse.dim_indicator AS i ON i.indicator_key = f.indicator_key
    JOIN warehouse.dim_time AS t ON t.time_key = f.time_key
    GROUP BY i.indicator_code
),
lag AS (
    SELECT l.indicator_code,
           l.latest_period,
           r.max_lag_months,
           -- whole months from the end of the latest period to :as_of
           extract(year FROM age(CAST(:as_of AS date), l.latest_end)) * 12
               + extract(month FROM age(CAST(:as_of AS date), l.latest_end)) AS lag_months
    FROM latest AS l
    JOIN qc_rule AS r ON r.indicator_code = l.indicator_code
    WHERE r.max_lag_months IS NOT NULL
)
SELECT indicator_code AS subject,
       format('latest period %s ended %s months before %s (expected at most %s)',
              latest_period, lag_months, CAST(:as_of AS date), max_lag_months) AS detail
FROM lag
WHERE lag_months > max_lag_months
ORDER BY subject;
