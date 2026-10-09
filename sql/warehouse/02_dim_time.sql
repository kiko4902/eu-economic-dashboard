-- Monthly calendar. Annual and quarterly observations map to the first month of their period.
-- Populated by sql/warehouse/seed/dim_time.sql.
CREATE TABLE IF NOT EXISTS warehouse.dim_time (
    time_key      integer  PRIMARY KEY,
    period_date   date     NOT NULL UNIQUE CHECK (extract(day FROM period_date) = 1),
    year          smallint NOT NULL CHECK (year BETWEEN 1990 AND 2100),
    quarter       smallint NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month         smallint NOT NULL CHECK (month BETWEEN 1 AND 12),
    month_name    text     NOT NULL,
    period_label  text     NOT NULL UNIQUE CHECK (period_label ~ '^\d{4}-\d{2}$'),
    quarter_label text     NOT NULL CHECK (quarter_label ~ '^\d{4}-Q[1-4]$'),
    CONSTRAINT dim_time_key_matches_date CHECK (time_key = year * 10000 + month * 100 + 1),
    CONSTRAINT dim_time_quarter_matches_month CHECK (quarter = (month + 2) / 3)
);

COMMENT ON TABLE warehouse.dim_time IS
    'Time dimension: one row per month from 2010-01 to the end of the current year.';
COMMENT ON COLUMN warehouse.dim_time.time_key IS
    'YYYYMMDD of the first day of the month, e.g. 20240101.';
COMMENT ON COLUMN warehouse.dim_time.period_date IS 'First day of the month.';
COMMENT ON COLUMN warehouse.dim_time.year IS 'Calendar year.';
COMMENT ON COLUMN warehouse.dim_time.quarter IS 'Calendar quarter (1-4).';
COMMENT ON COLUMN warehouse.dim_time.month IS 'Month number (1-12).';
COMMENT ON COLUMN warehouse.dim_time.month_name IS 'Short English month name, e.g. Jan.';
COMMENT ON COLUMN warehouse.dim_time.period_label IS
    'Month label YYYY-MM, as in Eurostat monthly TIME_PERIOD.';
COMMENT ON COLUMN warehouse.dim_time.quarter_label IS
    'Quarter label YYYY-Qn, as in Eurostat quarterly TIME_PERIOD.';
