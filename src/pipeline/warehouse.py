"""Warehouse: create the star schema and populate the dimension tables.

Idempotent: DDL uses IF NOT EXISTS, seeds are MERGE upserts that skip unchanged rows, and
dim_time only inserts missing months. Everything runs in one transaction.
"""

import csv
import logging
import sys

from sqlalchemy import Connection, Engine, text

from pipeline import config
from pipeline.db import execute_script, get_engine, read_sql, sql_files
from pipeline.logs import configure_logging

logger = logging.getLogger(__name__)

# Seeded dimensions: seeds/<name>.csv is upserted row by row with sql/warehouse/seed/<name>.sql.
SEEDED_DIMENSIONS = ("dim_country", "dim_indicator", "dim_flag")
WAREHOUSE_TABLES = ("dim_country", "dim_time", "dim_indicator", "dim_flag", "fact_observation")


def read_seed(name: str) -> list[dict[str, str]]:
    """Rows of seeds/<name>.csv as dicts of strings (empty string = missing value)."""
    with open(config.SEEDS_DIR / f"{name}.csv", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def apply_ddl(conn: Connection) -> None:
    for path in sql_files("warehouse"):
        logger.info("Applying %s", path.name)
        execute_script(conn, path)


def seed_dimension(conn: Connection, name: str) -> None:
    rows = read_seed(name)
    conn.execute(text(read_sql(f"warehouse/seed/{name}.sql")), rows)
    logger.info("Seeded %s from %d rows", name, len(rows))


def populate_dim_time(conn: Connection) -> None:
    conn.execute(text(read_sql("warehouse/seed/dim_time.sql")), {"start_year": config.START_YEAR})


def row_counts(conn: Connection) -> dict[str, int]:
    return {
        table: conn.execute(
            text(read_sql("warehouse/queries/row_count.sql", table=table))
        ).scalar_one()
        for table in WAREHOUSE_TABLES
    }


def populate_warehouse(conn: Connection) -> None:
    """Create warehouse tables and functions and populate the dimensions (caller's transaction)."""
    apply_ddl(conn)
    for name in SEEDED_DIMENSIONS:
        seed_dimension(conn, name)
    populate_dim_time(conn)


def build_warehouse(engine: Engine) -> dict[str, int]:
    """Create and populate the warehouse in one transaction; return row counts per table."""
    with engine.begin() as conn:
        populate_warehouse(conn)
        return row_counts(conn)


def main() -> int:
    configure_logging()
    counts = build_warehouse(get_engine())
    logger.info("Warehouse ready: %s", ", ".join(f"{t}={n}" for t, n in counts.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
