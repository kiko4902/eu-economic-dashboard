-- Index-like and level indicators rebased to 2015 = 100 (annual, complete years), so they can
-- share one chart: value / value in 2015 * 100.
--   - HICP_INDEX (2025 = 100) and HOUSE_PRICE_INDEX (2015 = 100): annual average index
--   - WAGE_NAC, WAGE_EUR, NET_EARNINGS, GDP_PC_PPS: rebased from levels
-- Rates (unemployment, inflation) are not indices and are left out. A country without a 2015
-- value has no rows for that indicator.
CREATE OR REPLACE VIEW analytics.v_index_base_2015 AS
WITH with_base AS (
    SELECT a.*,
           max(a.value) FILTER (WHERE a.year = 2015) OVER w               AS base_value,
           bool_or(a.has_provisional) FILTER (WHERE a.year = 2015) OVER w AS base_has_provisional,
           bool_or(a.has_estimated) FILTER (WHERE a.year = 2015) OVER w   AS base_has_estimated,
           bool_or(a.has_break) FILTER (WHERE a.year = 2015) OVER w       AS base_has_break
    FROM analytics.v_annual_summary AS a
    WHERE a.indicator_code IN ('HICP_INDEX', 'HOUSE_PRICE_INDEX', 'WAGE_NAC', 'WAGE_EUR',
                               'NET_EARNINGS', 'GDP_PC_PPS')
    WINDOW w AS (PARTITION BY a.country_code, a.indicator_code)
)
SELECT country_code,
       country_name,
       region,
       is_eu_member,
       is_aggregate,
       indicator_code,
       indicator_name,
       year,
       value                                      AS original_value,
       unit                                       AS original_unit,
       value / base_value * 100                   AS index_2015,
       has_provisional OR base_has_provisional    AS has_provisional,
       has_estimated OR base_has_estimated        AS has_estimated,
       has_break OR base_has_break                AS has_break
FROM with_base
WHERE base_value IS NOT NULL;

COMMENT ON VIEW analytics.v_index_base_2015 IS
    'Annual indices and levels rebased to 2015 = 100 (value / 2015 value * 100) for '
    'cross-indicator charts. HICP is rebased from 2025 = 100, wages/earnings/GDP from levels.';
COMMENT ON COLUMN analytics.v_index_base_2015.original_value IS
    'Annual value before rebasing (see original_unit).';
COMMENT ON COLUMN analytics.v_index_base_2015.index_2015 IS
    'Index, 2015 = 100: 130 means 30 % higher than in 2015.';
COMMENT ON COLUMN analytics.v_index_base_2015.has_provisional IS
    'This year''s or the 2015 value contains a provisional observation.';
