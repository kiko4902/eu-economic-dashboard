"""Reconciliation of raw rows against fact rows (run as the quality check "reconciliation").

For each indicator: raw rows read = fact rows + rows skipped (null value, out of scope,
outside validity). For each raw dataset: raw rows = rows read by its indicators + rows no
indicator uses. The skip counts are recomputed from raw with the transform's own staging and
classification steps, inside savepoints that are rolled back; raw and fact rows are counted
directly. Any difference that the skip reasons do not explain is a problem.
"""

from dataclasses import dataclass

from sqlalchemy import Connection, text

from pipeline import config
from pipeline.db import read_sql
from pipeline.transform import (
    SKIP_REASONS,
    StageResult,
    dataset_of,
    indicator_files,
    stage_indicator,
)


@dataclass(frozen=True)
class Reconciliation:
    dataset: str
    indicator_code: str
    raw_rows: int  # raw rows selected by the indicator's filters
    skipped: dict[str, int]
    fact_rows: int

    @property
    def expected_fact_rows(self) -> int:
        return self.raw_rows - sum(self.skipped.values())

    @property
    def unexplained(self) -> int:
        return self.fact_rows - self.expected_fact_rows


@dataclass(frozen=True)
class DatasetBalance:
    dataset: str
    raw_rows: int  # all rows in raw.<dataset>
    rows_used: int  # rows read by the dataset's indicators

    @property
    def not_used(self) -> int:
        return self.raw_rows - self.rows_used


def _stage_all(conn: Connection) -> dict[str, StageResult]:
    """Stage every indicator without loading it; rolling back each savepoint drops the
    indicator's temp tables before the next one is staged."""
    stages = {}
    for code, path in indicator_files().items():
        savepoint = conn.begin_nested()
        stages[code] = stage_indicator(conn, code, path)
        savepoint.rollback()
    return stages


def reconcile(conn: Connection) -> tuple[list[Reconciliation], list[DatasetBalance]]:
    """Reconcile on the caller's connection; staging runs in savepoints that are rolled back."""
    stages = _stage_all(conn)
    fact_rows = dict(
        conn.execute(text(read_sql("quality/queries/fact_rows_per_indicator.sql"))).all()
    )
    raw_rows = {
        d.code: conn.execute(text(read_sql("raw/row_count.sql", table=d.table))).scalar_one()
        for d in config.DATASETS
    }

    rows = [
        Reconciliation(
            dataset=dataset_of(code).code,
            indicator_code=code,
            raw_rows=stage.rows_read,
            skipped=dict(stage.skipped),
            fact_rows=fact_rows.get(code, 0),
        )
        for code, stage in stages.items()
    ]
    balances = [
        DatasetBalance(
            dataset=d.code,
            raw_rows=raw_rows[d.code],
            rows_used=sum(r.raw_rows for r in rows if r.dataset == d.code),
        )
        for d in config.DATASETS
    ]
    return rows, balances


def format_reconciliation(rows: list[Reconciliation], balances: list[DatasetBalance]) -> str:
    header = ["dataset", "indicator", "raw", *SKIP_REASONS, "expected", "fact", "unexplained"]
    table = [header] + [
        [
            r.dataset,
            r.indicator_code,
            str(r.raw_rows),
            *(str(r.skipped[reason]) for reason in SKIP_REASONS),
            str(r.expected_fact_rows),
            str(r.fact_rows),
            str(r.unexplained),
        ]
        for r in rows
    ]
    widths = [max(len(row[i]) for row in table) for i in range(len(header))]
    lines = [
        "  ".join(
            cell.ljust(w) if i < 2 else cell.rjust(w)  # text left, counts right
            for i, (cell, w) in enumerate(zip(row, widths, strict=True))
        )
        for row in table
    ]
    lines.append("")
    lines += [
        f"{b.dataset}: raw rows {b.raw_rows} = used by indicators {b.rows_used}"
        f" + not used {b.not_used}"
        for b in balances
    ]
    return "\n".join(lines)


def problems(rows: list[Reconciliation], balances: list[DatasetBalance]) -> list[str]:
    found = [
        f"{r.indicator_code}: {r.unexplained:+d} fact rows not explained by skip reasons"
        for r in rows
        if r.unexplained != 0
    ]
    found += [
        f"{b.dataset}: indicators read {b.rows_used} rows but raw has {b.raw_rows} (overlap)"
        for b in balances
        if b.not_used < 0
    ]
    return found
