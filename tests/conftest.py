"""Shared fixtures. Database tests run in a transaction that is always rolled back.

Without a reachable database the database tests are skipped, unless REQUIRE_DB=1 is set (as in
CI): then they fail, so a broken database setup can never pass silently.
"""

import os
from collections.abc import Iterator

import pytest
from sqlalchemy import Connection, Engine
from sqlalchemy.exc import OperationalError

from pipeline.analytics import create_reader_role, create_views
from pipeline.db import ensure_schemas, execute_script, get_engine, sql_files
from pipeline.warehouse import populate_warehouse


@pytest.fixture(scope="session")
def database() -> Engine | str:
    """Engine for the project database, or why it is not reachable (checked once)."""
    try:
        engine = get_engine(connect_timeout=3)
        with engine.connect():
            pass
    except (RuntimeError, OperationalError) as exc:
        return f"PostgreSQL not available (run `make up`): {str(exc).splitlines()[0]}"
    return engine


@pytest.fixture
def engine(database: Engine | str) -> Engine:
    if isinstance(database, str):
        if os.getenv("REQUIRE_DB") == "1":
            pytest.fail(f"REQUIRE_DB=1 but {database}", pytrace=False)
        pytest.skip(database)
    return database


@pytest.fixture
def db(engine: Engine) -> Iterator[Connection]:
    """Connection with raw tables, populated warehouse, analytics views and the reader role;
    every change is rolled back."""
    with engine.connect() as conn:
        transaction = conn.begin()
        try:
            ensure_schemas(conn)
            for path in sql_files("raw/tables"):
                execute_script(conn, path)
            populate_warehouse(conn)
            create_views(conn)
            create_reader_role(conn, password="test-only")
            yield conn
        finally:
            transaction.rollback()
