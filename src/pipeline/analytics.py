"""Analytics: create the views in the analytics schema and the read-only Power BI role.

Views are plain views, one file per view in sql/analytics/, applied in file-name order
(NN_<view>.sql), which is their dependency order. CREATE OR REPLACE VIEW keeps them in sync
with the files; changing or removing a view's columns needs a DB reset (like table DDL).
"""

import logging
import sys

from sqlalchemy import Connection, Engine, text

from pipeline import config
from pipeline.db import ensure_schemas, execute_script, get_engine, read_sql, sql_files
from pipeline.logs import configure_logging

logger = logging.getLogger(__name__)

READER_ROLE = "powerbi_reader"


def view_names() -> list[str]:
    """View names in dependency order, from the file names NN_<view>.sql."""
    return [path.stem.split("_", 1)[1] for path in sql_files("analytics")]


def create_views(conn: Connection) -> None:
    ensure_schemas(conn)
    for path in sql_files("analytics"):
        logger.info("Creating view %s", path.stem.split("_", 1)[1])
        execute_script(conn, path)


def create_reader_role(conn: Connection, password: str) -> None:
    """Create or update the read-only role (SELECT on analytics only)."""
    conn.execute(text(read_sql("roles/powerbi_reader_password.sql")), {"password": password})
    execute_script(conn, config.SQL_DIR / "roles" / f"{READER_ROLE}.sql")
    logger.info("Role %s: SELECT on analytics, no access to raw/warehouse", READER_ROLE)


def view_row_counts(conn: Connection) -> dict[str, int]:
    return {
        view: conn.execute(
            text(read_sql("analytics/queries/row_count.sql", view=view))
        ).scalar_one()
        for view in view_names()
    }


def build_analytics(engine: Engine, reader_password: str) -> dict[str, int]:
    """Create views and the reader role in one transaction; return row counts per view."""
    with engine.begin() as conn:
        create_views(conn)
        create_reader_role(conn, reader_password)
        return view_row_counts(conn)


def main() -> int:
    configure_logging()
    counts = build_analytics(get_engine(), config.load_reader_password())
    logger.info("Analytics ready: %s", ", ".join(f"{v}={n}" for v, n in counts.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
