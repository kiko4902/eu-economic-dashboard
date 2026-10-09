-- House prices vs wages, both 2015 = 100 and both in national-currency terms (the house price
-- index tracks prices in national currency, WAGE_NAC is in national currency), so the ratio is
-- free of exchange-rate effects. affordability_ratio > 100: house prices rose faster than wages
-- since 2015, i.e. housing became less affordable relative to wages.
CREATE OR REPLACE VIEW analytics.v_housing_affordability AS
WITH pivoted AS (
    SELECT country_code,
           country_name,
           region,
           is_eu_member,
           is_aggregate,
           year,
           max(index_2015) FILTER (WHERE indicator_code = 'HOUSE_PRICE_INDEX') AS house_price_index_2015,
           max(index_2015) FILTER (WHERE indicator_code = 'WAGE_NAC')          AS wage_index_2015,
           bool_or(has_provisional)                                           AS has_provisional,
           bool_or(has_estimated)                                             AS has_estimated,
           bool_or(has_break)                                                 AS has_break
    FROM analytics.v_index_base_2015
    WHERE indicator_code IN ('HOUSE_PRICE_INDEX', 'WAGE_NAC')
    GROUP BY country_code, country_name, region, is_eu_member, is_aggregate, year
)
SELECT country_code,
       country_name,
       region,
       is_eu_member,
       is_aggregate,
       year,
       house_price_index_2015,
       wage_index_2015,
       house_price_index_2015 / wage_index_2015 * 100 AS affordability_ratio,
       has_provisional,
       has_estimated,
       has_break
FROM pivoted
WHERE house_price_index_2015 IS NOT NULL
  AND wage_index_2015 IS NOT NULL;

COMMENT ON VIEW analytics.v_housing_affordability IS
    'House price index vs wage index (WAGE_NAC), both 2015 = 100 and both in national-currency '
    'terms, so they are comparable. affordability_ratio > 100 means housing became less '
    'affordable relative to wages than in 2015. Greece (no house prices) and the Netherlands '
    '(no wages) are missing.';
COMMENT ON COLUMN analytics.v_housing_affordability.house_price_index_2015 IS
    'House price index, annual average, 2015 = 100.';
COMMENT ON COLUMN analytics.v_housing_affordability.wage_index_2015 IS
    'Average full-time adjusted salary in national currency, 2015 = 100.';
COMMENT ON COLUMN analytics.v_housing_affordability.affordability_ratio IS
    'house_price_index_2015 / wage_index_2015 * 100; > 100 = less affordable than in 2015.';
