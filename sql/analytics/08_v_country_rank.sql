-- Rank of the EU-27 member states (the EU aggregate excluded) per indicator and year; rank 1 is
-- the best. The direction is set per indicator in ranking_rules. Only measures that are
-- comparable across countries are ranked: WAGE_NAC (different currencies), HICP_INDEX and
-- HOUSE_PRICE_INDEX (index levels depend on the base year, not on price levels) are not.
CREATE OR REPLACE VIEW analytics.v_country_rank AS
WITH ranking_rules (indicator_code, higher_is_better) AS (
    VALUES ('WAGE_EUR', true),
           ('NET_EARNINGS', true),
           ('GDP_PC_PPS', true),
           ('REAL_WAGE_GROWTH', true),
           ('UNEMPLOYMENT_RATE', false),
           ('HICP_INFLATION', false),
           ('HOUSING_AFFORDABILITY', false)
),
measures AS (
    SELECT country_code, country_name, is_eu_member, indicator_code, indicator_name, unit,
           year, value, has_provisional, has_estimated, has_break
    FROM analytics.v_annual_summary
    UNION ALL
    SELECT country_code, country_name, is_eu_member, 'REAL_WAGE_GROWTH',
           'Real wage growth', '% change on previous year', year, real_wage_growth_pct,
           has_provisional, has_estimated, has_break
    FROM analytics.v_real_wage_growth
    WHERE real_wage_growth_pct IS NOT NULL
    UNION ALL
    SELECT country_code, country_name, is_eu_member, 'HOUSING_AFFORDABILITY',
           'House prices relative to wages', 'Ratio, 2015 = 100', year, affordability_ratio,
           has_provisional, has_estimated, has_break
    FROM analytics.v_housing_affordability
)
SELECT m.country_code,
       m.country_name,
       m.indicator_code,
       m.indicator_name,
       m.unit,
       m.year,
       m.value,
       r.higher_is_better,
       rank() OVER (
           PARTITION BY m.indicator_code, m.year
           ORDER BY CASE WHEN r.higher_is_better THEN -m.value ELSE m.value END
       )                                                              AS country_rank,
       count(*) OVER (PARTITION BY m.indicator_code, m.year)           AS countries_ranked,
       m.has_provisional,
       m.has_estimated,
       m.has_break
FROM measures AS m
JOIN ranking_rules AS r ON r.indicator_code = m.indicator_code
WHERE m.is_eu_member;

COMMENT ON VIEW analytics.v_country_rank IS
    'Rank of EU-27 member states per indicator and year (1 = best; ties share a rank). '
    'Direction per indicator: higher is better for wages in EUR, net earnings, GDP per capita '
    'and real wage growth; lower is better for unemployment, inflation and house prices '
    'relative to wages.';
COMMENT ON COLUMN analytics.v_country_rank.higher_is_better IS
    'Ranking direction: true = the highest value ranks 1.';
COMMENT ON COLUMN analytics.v_country_rank.country_rank IS
    'Rank among the member states with a value for this indicator and year (1 = best).';
COMMENT ON COLUMN analytics.v_country_rank.countries_ranked IS
    'Number of member states with a value; fewer than 27 means missing data (e.g. NL wages, '
    'EL house prices, latest year not yet published everywhere).';
