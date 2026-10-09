"""Tests for the dimension seed files in seeds/ (no database needed)."""

from collections import Counter

import pytest

from pipeline import config
from pipeline.warehouse import read_seed

REGIONS = {"Northern Europe", "Western Europe", "Southern Europe", "Eastern Europe"}
NON_EURO = {"CZ", "DK", "HU", "PL", "RO", "SE"}


@pytest.fixture(scope="module")
def countries() -> dict[str, dict[str, str]]:
    return {row["country_code"]: row for row in read_seed("dim_country")}


@pytest.fixture(scope="module")
def indicators() -> dict[str, dict[str, str]]:
    return {row["indicator_code"]: row for row in read_seed("dim_indicator")}


# --- dim_country ----------------------------------------------------------------------------


def test_countries_are_eu27_plus_one_aggregate(countries: dict[str, dict[str, str]]) -> None:
    members = {c for c, r in countries.items() if r["is_eu_member"] == "true"}
    aggregates = {c for c, r in countries.items() if r["is_aggregate"] == "true"}

    assert len(countries) == 28
    assert members == config.EU27_COUNTRIES
    assert aggregates == {config.EU_AGGREGATE}
    assert set(countries) == config.GEO_SCOPE


def test_euro_adoption_years(countries: dict[str, dict[str, str]]) -> None:
    years = {c: r["euro_adoption_year"] for c, r in countries.items()}

    assert years["HR"] == "2023"
    assert years["BG"] == "2026"
    assert years["EL"] == "2001"
    assert {c for c, y in years.items() if y == ""} == NON_EURO | {config.EU_AGGREGATE}
    assert sum(1 for y in years.values() if y) == 21  # euro area members in 2026


def test_regions_follow_un_geoscheme(countries: dict[str, dict[str, str]]) -> None:
    regions = Counter(r["region"] for r in countries.values() if r["is_aggregate"] == "false")

    assert set(regions) == REGIONS
    assert regions == {
        "Northern Europe": 7,
        "Western Europe": 6,
        "Southern Europe": 8,  # incl. Cyprus (UN M49: Western Asia), see docs/data_sources.md
        "Eastern Europe": 6,
    }
    assert countries["HR"]["region"] == "Southern Europe"
    assert countries[config.EU_AGGREGATE]["region"] == ""


def test_iso_codes_are_unique_and_greece_is_gr(countries: dict[str, dict[str, str]]) -> None:
    iso = [r["iso_alpha2"] for r in countries.values() if r["is_aggregate"] == "false"]

    assert len(set(iso)) == 27
    assert all(len(code) == 2 and code.isupper() for code in iso)
    assert countries["EL"]["iso_alpha2"] == "GR"


# --- dim_indicator --------------------------------------------------------------------------


def test_indicators_match_dataset_config(indicators: dict[str, dict[str, str]]) -> None:
    assert len(indicators) == 8
    assert {(code, d.code) for d in config.DATASETS for code in d.indicator_codes} == {
        (code, row["source_dataset"]) for code, row in indicators.items()
    }


def test_indicator_filters_are_within_extract_filters(
    indicators: dict[str, dict[str, str]],
) -> None:
    """Every dimension the extract filters is pinned to one of its extracted codes."""
    for dataset in config.DATASETS:
        for code in dataset.indicator_codes:
            row = indicators[code]
            filters = dict(item.split("=") for item in row["source_filters"].split(", "))

            for dimension, extracted in dataset.filters.items():
                assert filters[dimension] in extracted.split(","), (code, dimension)
            assert row["frequency"] == filters["freq"]


def test_wages_split_by_currency(indicators: dict[str, dict[str, str]]) -> None:
    assert "unit=NAC" in indicators["WAGE_NAC"]["source_filters"]
    assert "unit=EUR" in indicators["WAGE_EUR"]["source_filters"]
    assert "unit=I25" in indicators["HICP_INDEX"]["source_filters"]


def test_net_earnings_cut_off_at_2023(indicators: dict[str, dict[str, str]]) -> None:
    row = indicators["NET_EARNINGS"]

    assert row["valid_to_year"] == "2023"
    assert "2024" in row["notes"]
    assert all(r["valid_to_year"] == "" for c, r in indicators.items() if c != "NET_EARNINGS")


def test_known_gaps_are_documented(indicators: dict[str, dict[str, str]]) -> None:
    assert "Greece" in indicators["HOUSE_PRICE_INDEX"]["notes"]
    assert "Netherlands" in indicators["WAGE_NAC"]["notes"]
    assert "Netherlands" in indicators["WAGE_EUR"]["notes"]


# --- dim_flag -------------------------------------------------------------------------------


def test_flags_include_no_flag_and_common_codes() -> None:
    flags = {row["flag_code"]: row["description"] for row in read_seed("dim_flag")}

    assert flags[""] == "no flag"
    assert {"b", "d", "e", "p", "u", "bp", "ep"} <= set(flags)
    assert len(flags) == len(read_seed("dim_flag"))  # codes are unique
    assert all(code.isalpha() and code.islower() for code in flags if code)
