"""Transform: load warehouse.fact_observation from the raw tables, one indicator at a time.

Each indicator has a file sql/transform/NN_<indicator_code>.sql that selects its raw rows into
a staging table. Shared steps in sql/transform/steps/ then map geo, period and flag to
dimension keys, apply the indicator's validity years and synchronise the fact rows. Every
indicator runs in its own transaction; a mapping problem rolls that indicator back.

Idempotent: the load inserts new rows, updates changed ones, deletes rows that disappeared from
the source and leaves unchanged rows untouched.
"""

import logging
import sys
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import Connection, CursorResult, Engine, text

from pipeline import config
from pipeline.config import SQL_DIR
from pipeline.db import describe_error, execute_script, get_engine, read_sql, sql_files
from pipeline.logs import configure_logging

logger = logging.getLogger(__name__)

SKIP_REASONS = ("null_value", "out_of_scope", "outside_validity")


class TransformError(Exception):
    """Raw rows of an indicator cannot be mapped to the warehouse dimensions."""


@dataclass(frozen=True)
class StageResult:
    """Raw rows read for one indicator and how many of them are skipped, per reason."""

    indicator_code: str
    rows_read: int
    rows_valid: int
    skipped: Mapping[str, int]


@dataclass(frozen=True)
class LoadResult:
    stage: StageResult
    inserted: int
    updated: int
    deleted: int


def indicator_files() -> dict[str, Path]:
    """Indicator code -> transform file, in run order (file name NN_<indicator_code>.sql)."""
    return {path.stem.split("_", 1)[1].upper(): path for path in sql_files("transform")}


def dataset_of(indicator_code: str) -> config.Dataset:
    return next(d for d in config.DATASETS if indicator_code in d.indicator_codes)


def _run(conn: Connection, step: str, indicator_code: str | None = None) -> CursorResult:
    params = {"indicator_code": indicator_code} if indicator_code else {}
    return conn.execute(text(read_sql(f"transform/steps/{step}.sql")), params)


def stage_indicator(conn: Connection, indicator_code: str, path: Path) -> StageResult:
    """Stage and classify an indicator's raw rows; raise TransformError if any cannot be mapped.

    Leaves the temp table stg_observation for load_indicator (dropped at transaction end).
    """
    if _run(conn, "00_indicator_exists", indicator_code).first() is None:
        raise TransformError(f"{indicator_code}: not in warehouse.dim_indicator (seed missing?)")
    execute_script(conn, SQL_DIR / "transform/steps/01_create_staging.sql")  # two statements
    conn.execute(text(path.read_text(encoding="utf-8")))
    _run(conn, "02_classify", indicator_code)

    problems = _run(conn, "03_check_mapping").all()
    if problems:
        details = "; ".join(f"{p.problem}: {p.value!r} ({p.row_count} rows)" for p in problems)
        raise TransformError(f"{indicator_code}: unmapped raw rows: {details}")

    summary = _run(conn, "04_summary").one()._mapping
    return StageResult(
        indicator_code=indicator_code,
        rows_read=summary["rows_read"],
        rows_valid=summary["rows_valid"],
        skipped={reason: summary[reason] for reason in SKIP_REASONS},
    )


def load_indicator(conn: Connection, indicator_code: str, path: Path) -> LoadResult:
    stage = stage_indicator(conn, indicator_code, path)
    counts = _run(conn, "05_load", indicator_code).one()
    if counts.rows_loaded != stage.rows_valid:
        raise AssertionError(f"{indicator_code}: loaded {counts.rows_loaded} != valid rows")
    return LoadResult(stage, counts.inserted, counts.updated, counts.deleted)


def _log_result(result: LoadResult) -> None:
    stage = result.stage
    skipped = ", ".join(f"{reason}={n}" for reason, n in stage.skipped.items())
    logger.info(
        "%s: read %d, loaded %d (new %d, updated %d, deleted %d), skipped %d (%s)",
        stage.indicator_code,
        stage.rows_read,
        stage.rows_valid,
        result.inserted,
        result.updated,
        result.deleted,
        sum(stage.skipped.values()),
        skipped,
    )


def _log_null_values(results: list[LoadResult]) -> None:
    """Null observations skipped, summed per raw dataset."""
    per_dataset: dict[str, int] = {d.code: 0 for d in config.DATASETS}
    for result in results:
        dataset = dataset_of(result.stage.indicator_code).code
        per_dataset[dataset] += result.stage.skipped["null_value"]
    logger.info(
        "Null observations skipped per dataset: %s",
        ", ".join(f"{code}={n}" for code, n in per_dataset.items()),
    )


def run_transform(engine: Engine) -> tuple[list[LoadResult], list[str]]:
    """Load every indicator; return the results and the codes of indicators that failed."""
    results: list[LoadResult] = []
    failed: list[str] = []
    for indicator_code, path in indicator_files().items():
        try:
            with engine.begin() as conn:
                result = load_indicator(conn, indicator_code, path)
        except Exception as exc:  # noqa: BLE001 - log and continue with the other indicators
            logger.error(
                "%s: transform failed, fact rows unchanged: %s", indicator_code, describe_error(exc)
            )
            failed.append(indicator_code)
            continue
        _log_result(result)
        results.append(result)
    _log_null_values(results)
    return results, failed


def main() -> int:
    configure_logging()
    results, failed = run_transform(get_engine())
    if failed:
        logger.error("Transform finished with failures: %s", ", ".join(failed))
        return 1
    logger.info("Transform finished: %d indicators loaded", len(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
