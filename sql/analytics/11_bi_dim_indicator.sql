-- Indicator dimension for Power BI: the warehouse indicators plus the indicators derived in
-- the analytics views (HICP_INFLATION in v_annual_summary, REAL_WAGE_GROWTH and
-- HOUSING_AFFORDABILITY in v_country_rank), so every indicator_code in the analytics views has
-- exactly one row here.
CREATE OR REPLACE VIEW analytics.bi_dim_indicator AS
WITH warehouse_indicators AS (
    SELECT indicator_code,
           name                                         AS indicator_name,
           unit,
           frequency,
           source_dataset,
           false                                        AS is_derived,
           indicator_code IN ('HICP_ANNUAL_RATE', 'UNEMPLOYMENT_RATE') AS is_rate,
           notes,
           CAST(indicator_key AS integer)               AS sort_order
    FROM warehouse.dim_indicator
),
derived (indicator_code, indicator_name, unit, frequency, source_dataset, is_derived, is_rate,
         notes, sort_order) AS (
    VALUES ('HICP_INFLATION', 'Inflation (HICP, annual average)', '% change on previous year',
            'A', 'prc_hicp_minr', true, true,
            'Annual average HICP index / previous year''s annual average - 1 (Eurostat''s '
            'method). Complete years only, from 2011.',
            101),
           ('REAL_WAGE_GROWTH', 'Real wage growth', '% change on previous year',
            'A', 'nama_10_fte, prc_hicp_minr', true, true,
            '(1 + nominal WAGE_NAC growth) / (1 + HICP_INFLATION) - 1. In v_country_rank.',
            102),
           ('HOUSING_AFFORDABILITY', 'House prices relative to wages', 'Ratio, 2015 = 100',
            'A', 'prc_hpi_q, nama_10_fte', true, false,
            'House price index / WAGE_NAC index, both 2015 = 100; above 100 = less affordable '
            'than in 2015. In v_country_rank.',
            103)
)
SELECT * FROM warehouse_indicators
UNION ALL
SELECT * FROM derived;

COMMENT ON VIEW analytics.bi_dim_indicator IS
    'Power BI indicator dimension: warehouse indicators plus those derived in the analytics '
    'views (one row per indicator_code used anywhere in analytics).';
COMMENT ON COLUMN analytics.bi_dim_indicator.indicator_code IS
    'Key for relationships to the analytics views.';
COMMENT ON COLUMN analytics.bi_dim_indicator.indicator_name IS 'Display name.';
COMMENT ON COLUMN analytics.bi_dim_indicator.is_derived IS
    'Computed in the analytics views rather than loaded from Eurostat.';
COMMENT ON COLUMN analytics.bi_dim_indicator.is_rate IS
    'Values are already rates (%): show changes in percentage points, not %.';
COMMENT ON COLUMN analytics.bi_dim_indicator.notes IS 'Breaks, known gaps, cut-offs, method.';
COMMENT ON COLUMN analytics.bi_dim_indicator.sort_order IS
    'Display order: warehouse indicators first, derived ones after.';
