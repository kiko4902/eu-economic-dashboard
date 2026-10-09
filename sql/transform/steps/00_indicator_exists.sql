-- Key of indicator :indicator_code; no row means the seed and sql/transform/ are out of sync.
SELECT indicator_key FROM warehouse.dim_indicator WHERE indicator_code = :indicator_code;
