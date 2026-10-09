-- Helper functions used by the transform (sql/transform/). CREATE OR REPLACE keeps them in
-- sync with this file on every run.

-- First day of a Eurostat time period: '2024' -> 2024-01-01, '2024-Q2' -> 2024-04-01,
-- '2024-03' -> 2024-03-01. Any other format raises an error (the transform fails loudly).
CREATE OR REPLACE FUNCTION warehouse.period_start_date(period text)
RETURNS date
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    IF period ~ '^\d{4}$' THEN
        RETURN make_date(period::integer, 1, 1);
    ELSIF period ~ '^\d{4}-Q[1-4]$' THEN
        RETURN make_date(left(period, 4)::integer, right(period, 1)::integer * 3 - 2, 1);
    ELSIF period ~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
        RETURN make_date(left(period, 4)::integer, right(period, 2)::integer, 1);
    END IF;
    RAISE EXCEPTION 'Unrecognised Eurostat time period: "%"', period
        USING ERRCODE = 'invalid_datetime_format';
END;
$$;

-- Frequency of a Eurostat time period: 'A' (2024), 'Q' (2024-Q2) or 'M' (2024-03).
CREATE OR REPLACE FUNCTION warehouse.period_frequency(period text)
RETURNS char(1)
LANGUAGE plpgsql IMMUTABLE STRICT
AS $$
BEGIN
    PERFORM warehouse.period_start_date(period);  -- validates the format
    RETURN CASE
        WHEN period ~ '^\d{4}$' THEN 'A'
        WHEN period ~ '-Q' THEN 'Q'
        ELSE 'M'
    END;
END;
$$;

-- Canonical form of an observation flag, as used in dim_flag: NULL -> '' (no flag); separators
-- (comma, space, semicolon) removed; letters lower-cased, de-duplicated and sorted, so 'b,p',
-- 'P B' and 'pb' all become 'bp'. Eurostat sends combined flags already in this form ('bep').
-- Other characters are kept, so they cannot match dim_flag and the transform fails loudly.
CREATE OR REPLACE FUNCTION warehouse.normalize_flag(flag text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
    SELECT coalesce(string_agg(DISTINCT c COLLATE "C", '' ORDER BY c COLLATE "C"), '')
    FROM regexp_split_to_table(lower(regexp_replace(coalesce(flag, ''), '[\s,;]', '', 'g')), '')
         AS c
$$;

COMMENT ON FUNCTION warehouse.period_start_date(text) IS
    'First day of a Eurostat period (YYYY, YYYY-Qn, YYYY-MM); raises on any other format.';
COMMENT ON FUNCTION warehouse.period_frequency(text) IS
    'Frequency (A/Q/M) of a Eurostat period; raises on an unknown format.';
COMMENT ON FUNCTION warehouse.normalize_flag(text) IS
    'Canonical dim_flag code of a raw OBS_FLAG: separators removed, letters sorted, NULL -> ''''.';
