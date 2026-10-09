"""Tests for the transform: period parsing, flag mapping, validity cut-off, idempotency.

Database tests need PostgreSQL (`make up`) and are skipped without it. They load small fixture
rows into the raw tables inside a transaction that is rolled back, so real data is untouched.
"""

from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import Connection, MetaData, Table, func, select
from sqlalchemy.exc import DataError

from db_helpers import RawRow, load_raw, transform
from pipeline import config
from pipeline.transform import LoadResult, TransformError, indicator_files
from pipeline.warehouse import read_seed

# --- helpers --------------------------------------------------------------------------------


def load_raw_earnings(conn: Connection, rows: list[RawRow]) -> None:
    load_raw(conn, "NET_EARNINGS", rows)


def transform_net_earnings(conn: Connection) -> LoadResult:
    return transform(conn, "NET_EARNINGS")


def net_earnings_facts(conn: Connection) -> dict[tuple[str, int], tuple[Decimal, str]]:
    """(geo, year) -> (value, flag code) of the NET_EARNINGS fact rows."""
    md = MetaData()
    fact, country, time, indicator, flag = (
        Table(name, md, schema="warehouse", autoload_with=conn)
        for name in ("fact_observation", "dim_country", "dim_time", "dim_indicator", "dim_flag")
    )
    query = (
        select(country.c.country_code, time.c.year, fact.c.value, flag.c.flag_code)
        .join_from(fact, country, fact.c.country_key == country.c.country_key)
        .join(time, fact.c.time_key == time.c.time_key)
        .join(indicator, fact.c.indicator_key == indicator.c.indicator_key)
        .join(flag, fact.c.flag_key == flag.c.flag_key)
        .where(indicator.c.indicator_code == "NET_EARNINGS")
    )
    return {(geo, year): (value, code) for geo, year, value, code in conn.execute(query)}


def scalar(conn: Connection, expression: object) -> object:
    return conn.execute(select(expression)).scalar_one()


# --- transform files (no database) ----------------------------------------------------------


def test_one_transform_file_per_indicator() -> None:
    seeded = {row["indicator_code"] for row in read_seed("dim_indicator")}
    configured = {code for d in config.DATASETS for code in d.indicator_codes}

    assert set(indicator_files()) == seeded == configured


def test_transform_files_apply_the_documented_filters() -> None:
    """Each file reads its dataset's raw table with exactly the filters in dim_indicator."""
    for row in read_seed("dim_indicator"):
        sql = indicator_files()[row["indicator_code"]].read_text(encoding="utf-8")
        filters = dict(item.split("=") for item in row["source_filters"].split(", "))

        assert f"FROM raw.{row['source_dataset']}\n" in sql, row["indicator_code"]
        assert sql.count(" = '") == len(filters), row["indicator_code"]
        for dimension, code in filters.items():
            assert f"{dimension} = '{code}'" in sql, row["indicator_code"]


# --- period parsing -------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("period", "start", "frequency"),
    [
        ("2024", date(2024, 1, 1), "A"),
        ("2024-Q1", date(2024, 1, 1), "Q"),
        ("2024-Q2", date(2024, 4, 1), "Q"),
        ("2024-Q4", date(2024, 10, 1), "Q"),
        ("2024-01", date(2024, 1, 1), "M"),
        ("2024-12", date(2024, 12, 1), "M"),
    ],
)
def test_period_parsing(db: Connection, period: str, start: date, frequency: str) -> None:
    assert scalar(db, func.warehouse.period_start_date(period)) == start
    assert scalar(db, func.warehouse.period_frequency(period)) == frequency


@pytest.mark.parametrize("period", ["2024-13", "2024-00", "2024-Q5", "2024Q1", "2024M01", "24", ""])
def test_invalid_period_raises(db: Connection, period: str) -> None:
    with pytest.raises(DataError, match="Unrecognised Eurostat time period"):
        with db.begin_nested():
            scalar(db, func.warehouse.period_start_date(period))


# --- flag mapping ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw_flag", "flag_code"),
    [(None, ""), ("", ""), ("p", "p"), ("bp", "bp"), ("pb", "bp"), ("b,p", "bp"), ("B P", "bp")],
)
def test_normalize_flag(db: Connection, raw_flag: str | None, flag_code: str) -> None:
    assert scalar(db, func.warehouse.normalize_flag(raw_flag)) == flag_code


def test_flags_map_to_dim_flag(db: Connection) -> None:
    load_raw_earnings(
        db,
        [
            ("HR", "2020", "1", None),
            ("HR", "2021", "2", "p"),
            ("HR", "2022", "3", "b,p"),
            ("HR", "2023", "4", "pe"),
        ],
    )
    transform_net_earnings(db)

    flags = {year: code for (_, year), (_, code) in net_earnings_facts(db).items()}
    assert flags == {2020: "", 2021: "p", 2022: "bp", 2023: "ep"}


def test_unknown_flag_fails_loudly(db: Connection) -> None:
    load_raw_earnings(db, [("HR", "2020", "1", "x")])

    with pytest.raises(TransformError, match="unknown flag: 'x'"):
        transform_net_earnings(db)


def test_unknown_geo_fails_loudly(db: Connection) -> None:
    load_raw_earnings(db, [("HR", "2020", "1", None), ("XX", "2020", "1", None)])

    with pytest.raises(TransformError, match="unknown geo code: 'XX'"):
        transform_net_earnings(db)


def test_period_of_wrong_frequency_fails_loudly(db: Connection) -> None:
    load_raw_earnings(db, [("HR", "2020-01", "1", None)])

    with pytest.raises(TransformError, match="period frequency M differs"):
        transform_net_earnings(db)


# --- validity cut-off and skip reasons ------------------------------------------------------


def test_net_earnings_stop_at_2023(db: Connection) -> None:
    load_raw_earnings(
        db,
        [
            ("HR", "2021", None, None),
            ("HR", "2022", "11224.52", None),
            ("HR", "2023", "12601.07", None),
            ("HR", "2024", "1267.00", "b"),
            ("HR", "2025", "16892.00", None),
        ],
    )
    result = transform_net_earnings(db)

    assert net_earnings_facts(db) == {
        ("HR", 2022): (Decimal("11224.52"), ""),
        ("HR", 2023): (Decimal("12601.07"), ""),
    }
    assert result.stage.rows_read == 5
    assert result.stage.skipped == {"null_value": 1, "out_of_scope": 0, "outside_validity": 2}


# --- idempotency ----------------------------------------------------------------------------


def test_rerun_changes_nothing_and_applies_source_changes(db: Connection) -> None:
    rows = [("HR", "2021", "1", None), ("HR", "2022", "2", None), ("SI", "2022", "3", None)]
    load_raw_earnings(db, rows)
    transform_net_earnings(db)  # syncs with the fixture, whatever the fact table held before
    second = transform_net_earnings(db)

    assert len(net_earnings_facts(db)) == 3
    assert (second.inserted, second.updated, second.deleted) == (0, 0, 0)

    load_raw_earnings(db, [("HR", "2021", "1", None), ("HR", "2022", "2.5", "p")])
    third = transform_net_earnings(db)

    assert (third.inserted, third.updated, third.deleted) == (0, 1, 1)
    assert net_earnings_facts(db) == {
        ("HR", 2021): (Decimal("1"), ""),
        ("HR", 2022): (Decimal("2.5"), "p"),
    }
