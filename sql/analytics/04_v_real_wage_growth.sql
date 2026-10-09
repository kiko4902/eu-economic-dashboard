-- Real wage growth per country and year:
--   nominal growth = WAGE_NAC / previous year's WAGE_NAC - 1 (national currency, so no
--                    exchange-rate effects)
--   inflation      = HICP_INFLATION from v_annual_summary (annual average index ratio)
--   real growth    = (1 + nominal) / (1 + inflation) - 1   (not nominal - inflation)
-- real_wage_index_2010 chains the real growth rates from 2010 = 100; it is NULL once the
-- series has a gap, because the chain cannot continue across a missing year.
-- Built with a pivot and window functions (no self-joins), which keeps the view fast.
CREATE OR REPLACE VIEW analytics.v_real_wage_growth AS
WITH pivoted AS (
    SELECT country_code,
           country_name,
           region,
           is_eu_member,
           is_aggregate,
           year,
           max(value) FILTER (WHERE indicator_code = 'WAGE_NAC')                 AS wage_nac,
           max(value) FILTER (WHERE indicator_code = 'HICP_INFLATION')           AS inflation_pct,
           bool_or(has_provisional) FILTER (WHERE indicator_code = 'WAGE_NAC')   AS wage_provisional,
           bool_or(has_estimated) FILTER (WHERE indicator_code = 'WAGE_NAC')     AS wage_estimated,
           bool_or(has_break) FILTER (WHERE indicator_code = 'WAGE_NAC')         AS wage_break,
           bool_or(has_provisional) FILTER (WHERE indicator_code = 'HICP_INFLATION')
                                                                                 AS inflation_provisional,
           bool_or(has_estimated) FILTER (WHERE indicator_code = 'HICP_INFLATION')
                                                                                 AS inflation_estimated,
           bool_or(has_break) FILTER (WHERE indicator_code = 'HICP_INFLATION')   AS inflation_break
    FROM analytics.v_annual_summary
    WHERE indicator_code IN ('WAGE_NAC', 'HICP_INFLATION')
    GROUP BY country_code, country_name, region, is_eu_member, is_aggregate, year
),
wages AS (
    SELECT p.*,
           lag(p.year) OVER w             AS previous_year,
           lag(p.wage_nac) OVER w         AS previous_wage_nac,
           lag(p.wage_provisional) OVER w AS previous_wage_provisional,
           lag(p.wage_estimated) OVER w   AS previous_wage_estimated,
           lag(p.wage_break) OVER w       AS previous_wage_break
    FROM pivoted AS p
    WHERE p.wage_nac IS NOT NULL
    WINDOW w AS (PARTITION BY p.country_code ORDER BY p.year)
),
growth AS (
    SELECT w.*,
           CASE WHEN w.previous_year = w.year - 1 THEN w.previous_wage_nac END AS prior_wage_nac,
           CASE WHEN w.previous_year = w.year - 1
                THEN (w.wage_nac / w.previous_wage_nac - 1) * 100
           END                                                               AS nominal_wage_growth_pct,
           CASE WHEN w.previous_year = w.year - 1
                THEN ((w.wage_nac / w.previous_wage_nac) / (1 + w.inflation_pct / 100) - 1) * 100
           END                                                               AS real_wage_growth_pct
    FROM wages AS w
),
chained AS (
    SELECT g.*,
           -- Years since the first year with a real growth rate; equals year - 2010 if the
           -- series starts in 2010 and has no gap.
           count(g.real_wage_growth_pct) OVER c                 AS chained_years,
           min(g.year) OVER (PARTITION BY g.country_code)       AS first_year,
           -- Product of (1 + real growth) up to this year, as exp(sum(ln(...))).
           exp(sum(ln(1 + g.real_wage_growth_pct / 100)) OVER c) AS chain_factor
    FROM growth AS g
    WINDOW c AS (PARTITION BY g.country_code ORDER BY g.year)
)
SELECT country_code,
       country_name,
       region,
       is_eu_member,
       is_aggregate,
       year,
       wage_nac,
       prior_wage_nac                                          AS previous_wage_nac,
       nominal_wage_growth_pct,
       inflation_pct,
       real_wage_growth_pct,
       CASE
           WHEN first_year <> 2010 THEN NULL
           WHEN year = 2010 THEN 100
           WHEN chained_years = year - 2010 THEN 100 * chain_factor
       END                                                     AS real_wage_index_2010,
       wage_provisional OR coalesce(previous_wage_provisional, false)
           OR coalesce(inflation_provisional, false)           AS has_provisional,
       wage_estimated OR coalesce(previous_wage_estimated, false)
           OR coalesce(inflation_estimated, false)             AS has_estimated,
       wage_break OR coalesce(previous_wage_break, false)
           OR coalesce(inflation_break, false)                 AS has_break
FROM chained;

COMMENT ON VIEW analytics.v_real_wage_growth IS
    'Real wage growth per country and year from WAGE_NAC (gross average full-time adjusted '
    'salary, national currency) and HICP inflation: (1 + nominal) / (1 + inflation) - 1. '
    'Netherlands has no wage data; wage series may have unflagged LFS breaks (2020-2021).';
COMMENT ON COLUMN analytics.v_real_wage_growth.wage_nac IS
    'Average full-time adjusted salary, national currency per year.';
COMMENT ON COLUMN analytics.v_real_wage_growth.nominal_wage_growth_pct IS
    'Change of wage_nac on the previous year, %.';
COMMENT ON COLUMN analytics.v_real_wage_growth.inflation_pct IS
    'HICP annual average inflation, % (annual average index ratio).';
COMMENT ON COLUMN analytics.v_real_wage_growth.real_wage_growth_pct IS
    'Real wage growth, %: ((1 + nominal) / (1 + inflation) - 1) * 100.';
COMMENT ON COLUMN analytics.v_real_wage_growth.real_wage_index_2010 IS
    'Real wages, 2010 = 100, chained from real_wage_growth_pct; 120 = 20 % higher in real terms '
    'than in 2010. NULL after a gap in the series.';
COMMENT ON COLUMN analytics.v_real_wage_growth.has_provisional IS
    'A provisional observation in the wages (this or previous year) or the inflation figure.';
