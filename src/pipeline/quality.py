"""Data quality checks: python -m pipeline.quality [check ...]

Each check finds issues per subject (indicator or dataset). Checks have a severity:
  error   - any issue fails the run (exit code 1, which stops `make pipeline`)
  warning - issues are logged and recorded, the run still passes

Rules and known gaps come from seeds/quality_rules.csv and seeds/known_gaps.csv (the only place
where exceptions live). Results are written to quality.check_run / quality.check_result.

Checks (in run order):
  load_status         latest extract of every dataset succeeded                 error
  reconciliation      raw rows = fact rows + rows skipped for a known reason   error
  completeness        every country has every indicator from its start year     error
  missing_periods     no holes inside a country's series                        error
  value_range         values within plausible ranges                            error
  known_gaps_current  documented known gaps still match the data                warning
  freshness           latest period not older than expected                     warning
"""

import logging
import sys
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Literal

from sqlalchemy import Connection, Engine, text

from pipeline import config
from pipeline.db import execute_script, get_engine, read_sql
from pipeline.logs import configure_logging
from pipeline.reconciliation import format_reconciliation, reconcile
from pipeline.warehouse import read_seed

logger = logging.getLogger(__name__)

Severity = Literal["error", "warning"]
MAX_EXAMPLES = 5  # issues quoted in a result message


@dataclass(frozen=True)
class Issue:
    subject: str
    detail: str


@dataclass(frozen=True)
class CheckResult:
    check_name: str
    subject: str
    severity: Severity
    issues: tuple[str, ...]

    @property
    def status(self) -> str:
        if not self.issues:
            return "pass"
        return "fail" if self.severity == "error" else "warn"

    @property
    def message(self) -> str | None:
        if not self.issues:
            return None
        shown = "; ".join(self.issues[:MAX_EXAMPLES])
        more = len(self.issues) - MAX_EXAMPLES
        return f"{shown}; ... and {more} more" if more > 0 else shown


@dataclass(frozen=True)
class Check:
    name: str
    severity: Severity
    subjects: Callable[[], list[str]]  # what the check covers; each gets a result row
    find_issues: Callable[[Connection], list[Issue]]


# --- subjects -------------------------------------------------------------------------------


def indicator_codes() -> list[str]:
    return [row["indicator_code"] for row in read_seed("dim_indicator")]


def range_rule_codes() -> list[str]:
    return [row["indicator_code"] for row in read_seed("quality_rules")]


def freshness_rule_codes() -> list[str]:
    return [row["indicator_code"] for row in read_seed("quality_rules") if row["max_lag_months"]]


def dataset_codes() -> list[str]:
    return [d.code for d in config.DATASETS]


# --- issue finders --------------------------------------------------------------------------


def sql_check(name: str, **params: object) -> Callable[[Connection], list[Issue]]:
    """Issues from sql/quality/checks/<name>.sql, which returns (subject, detail) rows."""

    def find(conn: Connection) -> list[Issue]:
        rows = conn.execute(text(read_sql(f"quality/checks/{name}.sql")), params)
        return [Issue(row.subject, row.detail) for row in rows]

    return find


def reconciliation_issues(conn: Connection) -> list[Issue]:
    rows, balances = reconcile(conn)
    logger.info("Reconciliation raw -> fact:\n%s", format_reconciliation(rows, balances))
    issues = [
        Issue(
            r.indicator_code,
            f"{r.unexplained:+d} fact rows not explained by skip reasons "
            f"(raw {r.raw_rows}, skipped {sum(r.skipped.values())}, fact {r.fact_rows})",
        )
        for r in rows
        if r.unexplained != 0
    ]
    # An overlap is a dataset-level problem: report it on each of the dataset's indicators.
    issues += [
        Issue(code, f"{b.dataset}: indicators read {b.rows_used} rows but raw has {b.raw_rows}")
        for b in balances
        if b.not_used < 0
        for code in next(d for d in config.DATASETS if d.code == b.dataset).indicator_codes
    ]
    return issues


def build_checks(as_of: date) -> tuple[Check, ...]:
    return (
        Check(
            "load_status",
            "error",
            dataset_codes,
            sql_check("load_status", datasets=dataset_codes()),
        ),
        Check("reconciliation", "error", indicator_codes, reconciliation_issues),
        Check("completeness", "error", indicator_codes, sql_check("completeness")),
        Check("missing_periods", "error", indicator_codes, sql_check("missing_periods")),
        Check("value_range", "error", range_rule_codes, sql_check("value_range")),
        Check("known_gaps_current", "warning", indicator_codes, sql_check("known_gaps_current")),
        Check("freshness", "warning", freshness_rule_codes, sql_check("freshness", as_of=as_of)),
    )


CHECK_NAMES = tuple(check.name for check in build_checks(date.today()))


# --- running --------------------------------------------------------------------------------


def load_rules(conn: Connection) -> None:
    """Load the rule and known-gap seeds into temp tables and list the missing periods."""
    execute_script(conn, config.SQL_DIR / "quality" / "setup" / "create_rule_tables.sql")
    conn.execute(text(read_sql("quality/setup/insert_rule.sql")), read_seed("quality_rules"))
    conn.execute(text(read_sql("quality/setup/insert_known_gap.sql")), read_seed("known_gaps"))
    conn.execute(
        text(read_sql("quality/setup/missing_periods.sql")), {"start_year": config.START_YEAR}
    )


def run_checks(
    conn: Connection, names: Sequence[str] = CHECK_NAMES, as_of: date | None = None
) -> list[CheckResult]:
    """Run the named checks on the caller's transaction (nothing is written)."""
    unknown = set(names) - set(CHECK_NAMES)
    if unknown:
        raise ValueError(f"Unknown checks: {sorted(unknown)}; available: {CHECK_NAMES}")
    load_rules(conn)
    results = []
    for check in build_checks(as_of or date.today()):
        if check.name not in names:
            continue
        issues = check.find_issues(conn)
        unexpected = {i.subject for i in issues} - set(check.subjects())
        if unexpected:
            raise AssertionError(f"{check.name}: issues for unknown subjects {unexpected}")
        results += [
            CheckResult(
                check.name,
                subject,
                check.severity,
                tuple(i.detail for i in issues if i.subject == subject),
            )
            for subject in check.subjects()
        ]
    return results


def summarise(results: list[CheckResult]) -> tuple[str, int, int]:
    errors = sum(1 for r in results if r.status == "fail")
    warnings = sum(1 for r in results if r.status == "warn")
    status = "failed" if errors else "passed_with_warnings" if warnings else "passed"
    return status, errors, warnings


def save_results(conn: Connection, results: list[CheckResult], started_at: datetime) -> int:
    status, errors, warnings = summarise(results)
    run_id = conn.execute(
        text(read_sql("quality/log/insert_run.sql")),
        {"started_at": started_at, "status": status, "errors": errors, "warnings": warnings},
    ).scalar_one()
    conn.execute(
        text(read_sql("quality/log/insert_result.sql")),
        [
            {
                "run_id": run_id,
                "check_name": r.check_name,
                "subject": r.subject,
                "severity": r.severity,
                "status": r.status,
                "issue_count": len(r.issues),
                "message": r.message,
            }
            for r in results
        ],
    )
    return run_id


def format_results(results: list[CheckResult]) -> str:
    header = ["check", "subject", "severity", "status", "issues", "message"]
    table = [header] + [
        [r.check_name, r.subject, r.severity, r.status, str(len(r.issues)), r.message or ""]
        for r in results
    ]
    widths = [max(len(row[i]) for row in table) for i in range(len(header) - 1)]
    return "\n".join(
        "  ".join(cell.ljust(w) for cell, w in zip(row[:-1], widths, strict=True)) + "  " + row[-1]
        for row in table
    )


def run_quality(engine: Engine, names: Sequence[str] = CHECK_NAMES) -> tuple[int, str]:
    """Run checks, record them in the quality schema; return (run_id, status)."""
    started_at = datetime.now(UTC)
    with engine.begin() as conn:
        execute_script(conn, config.SQL_DIR / "quality" / "tables" / "quality_log.sql")
        results = run_checks(conn, names)
        run_id = save_results(conn, results, started_at)
    logger.info("Quality results (run %d):\n%s", run_id, format_results(results))
    for r in results:
        if r.status != "pass":
            log = logger.error if r.status == "fail" else logger.warning
            log("%s [%s] %s: %s", r.check_name, r.severity, r.subject, r.message)
    status, errors, warnings = summarise(results)
    logger.info("Quality run %d: %s (%d errors, %d warnings)", run_id, status, errors, warnings)
    return run_id, status


def main(argv: Sequence[str] | None = None) -> int:
    configure_logging()
    names = list(argv if argv is not None else sys.argv[1:]) or list(CHECK_NAMES)
    _, status = run_quality(get_engine(), names)
    return 1 if status == "failed" else 0


if __name__ == "__main__":
    sys.exit(main())
