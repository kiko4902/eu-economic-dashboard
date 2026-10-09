"""Database helpers: engine creation and loading SQL from .sql files."""

import re
from pathlib import Path

from sqlalchemy import URL, Engine, create_engine

from pipeline.config import SQL_DIR, DbSettings, load_db_settings

_IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*$")


def get_engine(settings: DbSettings | None = None) -> Engine:
    settings = settings or load_db_settings()
    url = URL.create(
        "postgresql+psycopg",
        username=settings.user,
        password=settings.password,
        host=settings.host,
        port=settings.port,
        database=settings.name,
    )
    return create_engine(url, future=True)


def read_sql(relative_path: str, **identifiers: str) -> str:
    """Read sql/<relative_path>, filling {placeholders} with validated identifiers.

    Only identifiers (e.g. table names from our own config) may be templated; values are
    always passed as bound parameters.
    """
    text = (SQL_DIR / relative_path).read_text(encoding="utf-8")
    for name, value in identifiers.items():
        if not _IDENTIFIER.match(value):
            raise ValueError(f"Invalid SQL identifier for {{{name}}}: {value!r}")
    return text.format(**identifiers) if identifiers else text


def sql_files(relative_dir: str) -> list[Path]:
    """All .sql files in sql/<relative_dir>, sorted by name."""
    return sorted((SQL_DIR / relative_dir).glob("*.sql"))
