-- One row per month from January of the start year (config.START_YEAR) to December of the
-- current year. Existing months are kept, so re-running only adds months when a new year
-- starts.
INSERT INTO warehouse.dim_time (
    time_key, period_date, year, quarter, month, month_name, period_label, quarter_label
)
SELECT CAST(to_char(d, 'YYYYMMDD') AS integer),
       CAST(d AS date),
       CAST(extract(year FROM d) AS smallint),
       CAST(extract(quarter FROM d) AS smallint),
       CAST(extract(month FROM d) AS smallint),
       to_char(d, 'Mon'),
       to_char(d, 'YYYY-MM'),
       to_char(d, 'YYYY-"Q"Q')
FROM generate_series(
         make_date(CAST(:start_year AS integer), 1, 1),
         date_trunc('year', current_date) + INTERVAL '11 months',
         INTERVAL '1 month'
     ) AS d
ON CONFLICT (time_key) DO NOTHING;
