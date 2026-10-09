-- Year-over-year change per country and indicator, on the complete-year annual data.
CREATE OR REPLACE VIEW analytics.v_yoy_change AS
WITH with_previous AS (
    SELECT a.*,
           lag(a.year) OVER w            AS previous_year,
           lag(a.value) OVER w           AS previous_value,
           lag(a.has_provisional) OVER w AS previous_has_provisional,
           lag(a.has_estimated) OVER w   AS previous_has_estimated,
           lag(a.has_break) OVER w       AS previous_has_break
    FROM analytics.v_annual_summary AS a
    WINDOW w AS (PARTITION BY a.country_code, a.indicator_code ORDER BY a.year)
)
SELECT country_code,
       country_name,
       region,
       is_eu_member,
       is_aggregate,
       indicator_code,
       indicator_name,
       unit,
       year,
       value,
       previous_value,
       value - previous_value                                     AS absolute_change,
       -- % change is meaningless for indicators that are already rates (use absolute_change,
       -- in percentage points) and undefined for a previous value of 0.
       CASE
           WHEN indicator_code IN ('UNEMPLOYMENT_RATE', 'HICP_INFLATION') THEN NULL
           ELSE (value / nullif(previous_value, 0) - 1) * 100
       END                                                        AS pct_change,
       has_provisional OR previous_has_provisional                AS has_provisional,
       has_estimated OR previous_has_estimated                    AS has_estimated,
       has_break OR previous_has_break                            AS has_break
FROM with_previous
WHERE previous_year = year - 1;  -- no change across a gap in the series

COMMENT ON VIEW analytics.v_yoy_change IS
    'Change on the previous year per country and indicator (annual, complete years only). '
    'Rows exist only where the previous year is present too.';
COMMENT ON COLUMN analytics.v_yoy_change.absolute_change IS
    'value - previous_value, in the indicator''s unit (percentage points for rates).';
COMMENT ON COLUMN analytics.v_yoy_change.pct_change IS
    'Change in %; NULL for indicators that are rates (UNEMPLOYMENT_RATE, HICP_INFLATION).';
COMMENT ON COLUMN analytics.v_yoy_change.has_provisional IS
    'A provisional observation in this or the previous year.';
COMMENT ON COLUMN analytics.v_yoy_change.has_estimated IS
    'An estimated observation in this or the previous year.';
COMMENT ON COLUMN analytics.v_yoy_change.has_break IS
    'A break in series in this or the previous year.';
