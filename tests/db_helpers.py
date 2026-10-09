"""Helpers for database tests: load fixture rows into raw tables and run the transform.

Use them only on the `db` fixture connection, whose transaction is always rolled back.
"""

from decimal import Decimal

import pandas as pd
from sqlalchemy import Connection, text

from pipeline.config import PROJECT_ROOT
from pipeline.db import read_sql
from pipeline.extract import replace_dataset
from pipeline.transform import LoadResult, dataset_of, indicator_files, load_indicator
from pipeline.warehouse import read_seed

TEST_SQL_DIR = PROJECT_ROOT / "tests" / "sql"

# (geo, time_period, value, flag); value as a string so it stays an exact Decimal
RawRow = tuple[str, str, str | None, str | None]


def indicator_filters(indicator_code: str) -> dict[str, str]:
    """Raw dimension codes of an indicator, from seeds/dim_indicator.csv source_filters."""
    row = next(r for r in read_seed("dim_indicator") if r["indicator_code"] == indicator_code)
    return dict(item.split("=") for item in row["source_filters"].split(", "))


def load_raw(conn: Connection, indicator_code: str, rows: list[RawRow]) -> None:
    """Replace the indicator's raw dataset with fixture rows carrying its dimension codes."""
    dataset = dataset_of(indicator_code)
    load_id = conn.execute(
        text(read_sql("raw/load_log_start.sql")), {"dataset": dataset.code}
    ).scalar_one()
    df = pd.DataFrame(
        [
            {
                **indicator_filters(indicator_code),
                "geo": geo,
                "time_period": period,
                "obs_value": None if value is None else Decimal(value),
                "obs_flag": flag,
                "conf_status": None,
            }
            for geo, period, value, flag in rows
        ]
    )
    replace_dataset(conn, dataset, df, load_id)


def transform(conn: Connection, indicator_code: str) -> LoadResult:
    return load_indicator(conn, indicator_code, indicator_files()[indicator_code])


def load_and_transform(conn: Connection, indicator_code: str, rows: list[RawRow]) -> LoadResult:
    load_raw(conn, indicator_code, rows)
    return transform(conn, indicator_code)


def months(
    geo: str, year: int, value: str, count: int = 12, flag: str | None = None
) -> list[RawRow]:
    """Monthly rows Jan..count of one year with the same value."""
    return [(geo, f"{year}-{m:02d}", value, flag) for m in range(1, count + 1)]


def run_test_sql(conn: Connection, name: str) -> None:
    """Run tests/sql/<name>.sql (e.g. SET ROLE) on the connection."""
    conn.execute(text((TEST_SQL_DIR / f"{name}.sql").read_text(encoding="utf-8")))
