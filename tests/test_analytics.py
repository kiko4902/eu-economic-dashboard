"""Tests for the analytics views and the Power BI role.

Database tests: fixture rows are loaded into raw, transformed and read back through the views,
inside a transaction that is rolled back (see conftest.py). Indicators not loaded here keep
whatever the database holds, so assertions only look at the fixture's rows.
"""

from collections.abc import Mapping
from typing import Any

import pytest
from sqlalchemy import Connection, MetaData, Table, column, func, select, table
from sqlalchemy.exc import ProgrammingError

from db_helpers import load_and_transform, months, run_test_sql
from pipeline.analytics import view_names

# --- helpers --------------------------------------------------------------------------------


def view_rows(conn: Connection, view: str, **filters: Any) -> list[Mapping[str, Any]]:
    """Rows of analytics.<view> matching column == value filters, ordered by year."""
    t = Table(view, MetaData(), schema="analytics", autoload_with=conn)
    query = select(t).where(*(t.c[column] == value for column, value in filters.items()))
    return [dict(row._mapping) for row in conn.execute(query.order_by(t.c.year))]


def by_year(rows: list[Mapping[str, Any]], column: str) -> dict[int, float | None]:
    return {r["year"]: None if r[column] is None else float(r[column]) for r in rows}


def quarters(geo: str, year: int, values: list[str]) -> list[tuple[str, str, str, None]]:
    return [(geo, f"{year}-Q{q}", v, None) for q, v in enumerate(values, start=1)]


# --- view files (no database) ---------------------------------------------------------------


def test_view_files_are_in_dependency_order() -> None:
    names = view_names()

    assert names[0] == "v_observations"
    assert names.index("v_annual_summary") < names.index("v_yoy_change")
    assert names.index("v_annual_summary") < names.index("v_real_wage_growth")
    assert names.index("v_index_base_2015") < names.index("v_housing_affordability")
    assert names.index("v_real_wage_growth") < names.index("v_country_rank")
    assert names.index("v_housing_affordability") < names.index("v_country_rank")
    assert names.index("v_annual_summary") < names.index("bi_dim_year")


# --- complete-year rule and flags -----------------------------------------------------------


def test_partial_years_are_excluded_from_annual_views(db: Connection) -> None:
    load_and_transform(
        db,
        "HICP_INDEX",
        months("HR", 2023, "100")
        + months("HR", 2024, "110")
        + months("HR", 2025, "120", count=7),  # partial year
    )
    load_and_transform(
        db,
        "HOUSE_PRICE_INDEX",
        quarters("HR", 2024, ["100", "102", "104", "106"])
        + quarters("HR", 2025, ["110", "112", "114"]),  # partial year
    )

    hicp = view_rows(db, "v_annual_summary", country_code="HR", indicator_code="HICP_INDEX")
    inflation = view_rows(
        db, "v_annual_summary", country_code="HR", indicator_code="HICP_INFLATION"
    )
    houses = view_rows(
        db, "v_annual_summary", country_code="HR", indicator_code="HOUSE_PRICE_INDEX"
    )

    assert by_year(hicp, "value") == {2023: 100.0, 2024: 110.0}
    assert [r["observation_count"] for r in hicp] == [12, 12]
    assert by_year(inflation, "value") == {2024: pytest.approx(10.0)}  # 2023 has no 2022
    assert by_year(houses, "value") == {2024: 103.0}
    yoy = view_rows(db, "v_yoy_change", country_code="HR")
    fixture_indicators = {"HICP_INDEX", "HICP_INFLATION", "HOUSE_PRICE_INDEX"}
    assert [r["year"] for r in yoy if r["indicator_code"] in fixture_indicators] == [2024]


def test_flags_are_carried_to_annual_views(db: Connection) -> None:
    hicp_2024 = months("HR", 2024, "110", count=11) + [("HR", "2024-12", "110", "p")]
    load_and_transform(db, "HICP_INDEX", months("HR", 2023, "100") + hicp_2024)

    hicp = view_rows(db, "v_annual_summary", country_code="HR", indicator_code="HICP_INDEX")
    inflation = view_rows(
        db, "v_annual_summary", country_code="HR", indicator_code="HICP_INFLATION"
    )

    assert {r["year"]: r["has_provisional"] for r in hicp} == {2023: False, 2024: True}
    assert inflation[0]["has_provisional"] is True
    assert inflation[0]["has_estimated"] is False


# --- real wage growth -----------------------------------------------------------------------


def test_real_wage_growth_formula_and_chained_index(db: Connection) -> None:
    load_and_transform(
        db,
        "WAGE_NAC",
        [("HR", "2010", "100", None), ("HR", "2011", "110", None), ("HR", "2012", "121", None)],
    )
    load_and_transform(
        db,
        "HICP_INDEX",
        months("HR", 2010, "100") + months("HR", 2011, "105") + months("HR", 2012, "105"),
    )

    rows = view_rows(db, "v_real_wage_growth", country_code="HR")

    assert by_year(rows, "nominal_wage_growth_pct") == {
        2010: None,
        2011: pytest.approx(10.0),
        2012: pytest.approx(10.0),
    }
    assert by_year(rows, "inflation_pct") == {
        2010: None,
        2011: pytest.approx(5.0),
        2012: pytest.approx(0.0),
    }
    # (1 + 10 %) / (1 + 5 %) - 1 = 4.76 %, not the simple difference 10 % - 5 % = 5 %
    assert by_year(rows, "real_wage_growth_pct") == {
        2010: None,
        2011: pytest.approx((1.10 / 1.05 - 1) * 100),
        2012: pytest.approx(10.0),
    }
    # chained: 100 * 1.10 / 1.05 * 1.10 = (121 / 100) / (105 / 100) * 100
    assert by_year(rows, "real_wage_index_2010") == {
        2010: 100.0,
        2011: pytest.approx(100 * 1.10 / 1.05),
        2012: pytest.approx(121 / 105 * 100),
    }


def test_real_wage_index_stops_at_a_gap(db: Connection) -> None:
    load_and_transform(
        db,
        "WAGE_NAC",
        [("HR", "2010", "100", None), ("HR", "2011", "110", None), ("HR", "2013", "120", None)],
    )
    load_and_transform(
        db, "HICP_INDEX", [r for y in range(2010, 2014) for r in months("HR", y, "100")]
    )

    rows = view_rows(db, "v_real_wage_growth", country_code="HR")

    assert by_year(rows, "real_wage_index_2010") == {
        2010: 100.0,
        2011: pytest.approx(110.0),
        2013: None,
    }
    assert by_year(rows, "nominal_wage_growth_pct")[2013] is None  # no 2012 to compare with


# --- rebasing and affordability -------------------------------------------------------------


def test_rebasing_to_2015_and_housing_affordability(db: Connection) -> None:
    load_and_transform(db, "WAGE_NAC", [("HR", "2015", "200", None), ("HR", "2016", "210", None)])
    load_and_transform(db, "HICP_INDEX", months("HR", 2015, "98") + months("HR", 2016, "107.8"))
    load_and_transform(
        db,
        "HOUSE_PRICE_INDEX",
        quarters("HR", 2015, ["99", "100", "101", "100"]) + quarters("HR", 2016, ["110"] * 4),
    )

    rebased = view_rows(db, "v_index_base_2015", country_code="HR")
    index = {(r["indicator_code"], r["year"]): float(r["index_2015"]) for r in rebased}

    assert index[("WAGE_NAC", 2015)] == 100.0
    assert index[("WAGE_NAC", 2016)] == pytest.approx(105.0)
    assert index[("HICP_INDEX", 2016)] == pytest.approx(110.0)  # from 2025 = 100 to 2015 = 100
    assert index[("HOUSE_PRICE_INDEX", 2016)] == pytest.approx(110.0)

    housing = view_rows(db, "v_housing_affordability", country_code="HR")
    assert by_year(housing, "affordability_ratio") == {
        2015: 100.0,
        2016: pytest.approx(110 / 105 * 100),  # > 100: prices rose faster than wages
    }


# --- country rank ---------------------------------------------------------------------------


def test_rank_direction_per_indicator(db: Connection) -> None:
    load_and_transform(
        db,
        "UNEMPLOYMENT_RATE",
        months("HR", 2024, "5") + months("SI", 2024, "4") + months("EU27_2020", 2024, "6"),
    )
    load_and_transform(
        db, "GDP_PC_PPS", [("HR", "2024", "30000", None), ("SI", "2024", "35000", None)]
    )

    ranks = {
        (r["indicator_code"], r["country_code"]): r["country_rank"]
        for r in view_rows(db, "v_country_rank", year=2024)
        if r["indicator_code"] in ("UNEMPLOYMENT_RATE", "GDP_PC_PPS")
    }

    assert ranks == {
        ("UNEMPLOYMENT_RATE", "SI"): 1,  # lower is better
        ("UNEMPLOYMENT_RATE", "HR"): 2,
        ("GDP_PC_PPS", "SI"): 1,  # higher is better
        ("GDP_PC_PPS", "HR"): 2,
    }  # the EU aggregate is not ranked


# --- Power BI role --------------------------------------------------------------------------


def test_reader_can_select_analytics_only(db: Connection) -> None:
    run_test_sql(db, "set_role_powerbi_reader")
    for view in view_names():
        db.execute(select(func.count()).select_from(table(view, schema="analytics")))

    for schema, relation in [
        ("warehouse", "fact_observation"),
        ("raw", "load_log"),
        ("quality", "check_result"),
    ]:
        with pytest.raises(ProgrammingError, match="permission denied"):
            with db.begin_nested():
                db.execute(select(func.count()).select_from(table(relation, schema=schema)))
    run_test_sql(db, "reset_role")


@pytest.mark.parametrize(
    ("schema", "allowed"),
    [("analytics", True), ("warehouse", False), ("raw", False), ("quality", False)],
)
def test_reader_schema_privileges(db: Connection, schema: str, allowed: bool) -> None:
    usage = func.has_schema_privilege("powerbi_reader", schema, "USAGE")
    create = func.has_schema_privilege("powerbi_reader", schema, "CREATE")

    assert db.execute(select(usage)).scalar_one() is allowed
    assert db.execute(select(create)).scalar_one() is False


def test_inflation_ranks_by_distance_from_2_percent(db: Connection) -> None:
    # 2023 averages 100 everywhere; 2024: HR +2.5 %, SI +1.0 %, PL -0.5 % (deflation), IT +6 %
    rows = []
    for geo, level_2024 in [("HR", "102.5"), ("SI", "101"), ("PL", "99.5"), ("IT", "106")]:
        rows += months(geo, 2023, "100") + months(geo, 2024, level_2024)
    load_and_transform(db, "HICP_INDEX", rows)

    ranks = {
        r["country_code"]: r["country_rank"]
        for r in view_rows(db, "v_country_rank", year=2024, indicator_code="HICP_INFLATION")
    }

    # distances from 2 %: HR 0.5, SI 1.0, PL 2.5, IT 4.0
    assert ranks == {"HR": 1, "SI": 2, "PL": 3, "IT": 4}


# --- Power BI dimensions and quality views ---------------------------------------------------

COUNTRY_COLUMNS = ("country_code", "country_name", "sort_order", "highlight_colour")


def all_rows(conn: Connection, view: str, *columns: str) -> list[Mapping[str, Any]]:
    """The given columns of every row of analytics.<view> (no reflection of the whole view)."""
    t = table(view, *(column(c) for c in columns), schema="analytics")
    return [dict(row._mapping) for row in conn.execute(select(t))]


def test_bi_dim_country_puts_croatia_and_eu_first(db: Connection) -> None:
    rows = sorted(all_rows(db, "bi_dim_country", *COUNTRY_COLUMNS), key=lambda r: r["sort_order"])

    assert [r["country_code"] for r in rows[:2]] == ["HR", "EU27_2020"]
    assert [r["sort_order"] for r in rows] == list(range(1, 29))
    assert len({r["country_code"] for r in rows}) == 28
    others = [r["country_name"] for r in rows[2:]]
    assert others == sorted(others)
    assert {r["country_code"]: r["highlight_colour"] for r in rows[:2]} == {
        "HR": "#C8102E",
        "EU27_2020": "#1F4E9E",
    }


def test_bi_dimensions_cover_every_key_in_the_fact_views(db: Connection) -> None:
    countries = {r["country_code"] for r in all_rows(db, "bi_dim_country", "country_code")}
    years = {r["year"] for r in all_rows(db, "bi_dim_year", "year")}
    indicators = {r["indicator_code"] for r in all_rows(db, "bi_dim_indicator", "indicator_code")}

    assert len(indicators) == len(all_rows(db, "bi_dim_indicator", "indicator_code"))  # unique
    assert years == set(range(min(years), max(years) + 1))  # no missing years
    for view in ("v_observations", "v_annual_summary", "v_country_rank"):
        rows = all_rows(db, view, "country_code", "indicator_code", "year")
        assert {r["country_code"] for r in rows} <= countries, view
        assert {r["indicator_code"] for r in rows} <= indicators, view
        assert {r["year"] for r in rows} <= years, view
    gaps = all_rows(db, "v_known_gaps", "country_code", "indicator_code")
    assert {r["country_code"] for r in gaps} <= countries
    assert {r["indicator_code"] for r in gaps} <= indicators


def test_quality_views_show_the_latest_run(db: Connection) -> None:
    from datetime import UTC, datetime

    from pipeline.quality import run_checks, save_results

    run_id = save_results(db, run_checks(db, ["value_range"]), datetime.now(UTC))

    latest = all_rows(db, "v_quality_latest", "run_id", "check_name")
    gaps = all_rows(
        db, "v_known_gaps", "run_id", "indicator_code", "country_code", "gap_description"
    )

    assert {r["run_id"] for r in latest} == {run_id}
    assert {r["check_name"] for r in latest} == {"value_range"}
    assert {r["run_id"] for r in gaps} == {run_id}
    assert ("HOUSE_PRICE_INDEX", "EL", "No data at all") in {
        (g["indicator_code"], g["country_code"], g["gap_description"]) for g in gaps
    }
