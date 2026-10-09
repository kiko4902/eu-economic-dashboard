"""Tests for the data quality checks.

Seed consistency and result logic run without a database. Database tests load fixture rows into
a transaction that is rolled back, run the checks on it and look at the affected subjects only
(other indicators keep whatever the database holds).
"""

from datetime import date

import pytest
from sqlalchemy import Connection, text

from db_helpers import load_and_transform, months
from pipeline import config
from pipeline.db import read_sql
from pipeline.quality import (
    CHECK_NAMES,
    CheckResult,
    build_checks,
    run_checks,
    summarise,
)
from pipeline.warehouse import read_seed

# --- seeds and result logic (no database) ---------------------------------------------------


def test_every_indicator_has_a_quality_rule() -> None:
    indicators = {row["indicator_code"] for row in read_seed("dim_indicator")}
    rules = {row["indicator_code"]: row for row in read_seed("quality_rules")}

    assert set(rules) == indicators | {"HICP_INFLATION"}
    for code, rule in rules.items():
        assert float(rule["min_value"]) < float(rule["max_value"]), code
    assert rules["UNEMPLOYMENT_RATE"]["min_value"] == "0"
    assert rules["UNEMPLOYMENT_RATE"]["max_value"] == "40"
    assert (rules["HICP_INFLATION"]["min_value"], rules["HICP_INFLATION"]["max_value"]) == (
        "-10",
        "30",
    )


def test_known_gaps_reference_real_indicators_and_countries() -> None:
    indicators = {row["indicator_code"] for row in read_seed("dim_indicator")}
    gaps = read_seed("known_gaps")

    assert {
        (g["indicator_code"], g["country_code"]) for g in gaps if g["gap_type"] == "no_series"
    } == {
        ("HOUSE_PRICE_INDEX", "EL"),
        ("WAGE_NAC", "NL"),
        ("WAGE_EUR", "NL"),
    }
    for gap in gaps:
        assert gap["indicator_code"] in indicators
        assert gap["country_code"] in config.GEO_SCOPE
        assert gap["gap_type"] in {"no_series", "missing_periods"}
        assert gap["reason"]
        assert bool(gap["from_period"]) == (gap["gap_type"] == "missing_periods")


def test_severity_decides_status_and_run_outcome() -> None:
    error = CheckResult("value_range", "X", "error", ("too high",))
    warning = CheckResult("freshness", "X", "warning", ("old",))
    passed = CheckResult("completeness", "X", "error", ())

    assert (error.status, warning.status, passed.status) == ("fail", "warn", "pass")
    assert summarise([passed, warning]) == ("passed_with_warnings", 0, 1)
    assert summarise([passed, warning, error]) == ("failed", 1, 1)
    assert summarise([passed]) == ("passed", 0, 0)


def test_message_quotes_the_first_issues() -> None:
    result = CheckResult("missing_periods", "X", "error", tuple(f"issue {i}" for i in range(8)))

    assert result.message == "issue 0; issue 1; issue 2; issue 3; issue 4; ... and 3 more"


def test_check_severities() -> None:
    severities = {c.name: c.severity for c in build_checks(date.today())}

    assert severities == {
        "load_status": "error",
        "reconciliation": "error",
        "completeness": "error",
        "missing_periods": "error",
        "value_range": "error",
        "known_gaps_current": "warning",
        "freshness": "warning",
    }
    assert CHECK_NAMES == tuple(severities)


# --- checks on fixture data (database) ------------------------------------------------------


def issues(conn: Connection, check: str, subject: str, as_of: date | None = None) -> list[str]:
    result = next(r for r in run_checks(conn, [check], as_of=as_of) if r.subject == subject)
    return list(result.issues)


def annual(geo: str, years: range | list[int], value: str = "20000") -> list:
    return [(geo, str(year), value, None) for year in years]


def test_value_out_of_range_fails(db: Connection) -> None:
    rows = months("HR", 2024, "5") + [("SI", "2024-01", "55", None)]
    load_and_transform(db, "UNEMPLOYMENT_RATE", rows)

    assert issues(db, "value_range", "UNEMPLOYMENT_RATE") == ["SI 2024-01: 55.00 outside [0, 40]"]


def test_late_start_fails_unless_it_is_a_known_gap(db: Connection) -> None:
    load_and_transform(
        db,
        "NET_EARNINGS",
        annual("HR", range(2013, 2024)) + annual("SI", range(2012, 2024)),
    )

    found = issues(db, "completeness", "NET_EARNINGS")

    assert "SI: starts late, missing 2010 to 2011 (2 periods)" in found
    assert not any(issue.startswith("HR:") for issue in found)  # known gap: starts 2013
    assert "AT: no data" in found  # not in the fixture, no known gap


def test_known_no_series_gap_is_not_reported(db: Connection) -> None:
    found = issues(db, "completeness", "HOUSE_PRICE_INDEX")

    assert not any(issue.startswith("EL:") for issue in found)


def test_hole_inside_a_series_fails_unless_it_is_a_known_gap(db: Connection) -> None:
    load_and_transform(
        db,
        "NET_EARNINGS",
        annual("SI", [2010, 2011, 2013])
        + annual("CY", [2014, 2017])  # 2015-2016 are a known gap
        + annual("HR", [2013, 2015]),
    )

    found = issues(db, "missing_periods", "NET_EARNINGS")

    assert found == ["HR: missing 2014", "SI: missing 2012"]


def test_known_gap_that_no_longer_applies_warns(db: Connection) -> None:
    load_and_transform(db, "NET_EARNINGS", annual("HR", range(2010, 2024)))

    found = issues(db, "known_gaps_current", "NET_EARNINGS")

    assert any(
        issue.startswith("HR: known gap (missing_periods 2010-01 to 2012-01)") for issue in found
    )
    results = run_checks(db, ["known_gaps_current"])
    assert {r.status for r in results if r.issues} == {"warn"}  # warning, never a failure


def test_freshness_warns_when_data_is_old(db: Connection) -> None:
    load_and_transform(db, "UNEMPLOYMENT_RATE", months("HR", 2024, "5"))

    assert issues(db, "freshness", "UNEMPLOYMENT_RATE", as_of=date(2025, 3, 15)) == []
    assert issues(db, "freshness", "UNEMPLOYMENT_RATE", as_of=date(2025, 6, 15)) == [
        "latest period 2024-12 ended 5 months before 2025-06-15 (expected at most 3)"
    ]


def test_failed_extract_fails_load_status(db: Connection) -> None:
    load_id = db.execute(
        text(read_sql("raw/load_log_start.sql")), {"dataset": "une_rt_m"}
    ).scalar_one()
    db.execute(
        text(read_sql("raw/load_log_finish.sql")),
        {"load_id": load_id, "status": "failed", "rows_loaded": 0, "error_message": "HTTP 500"},
    )

    found = issues(db, "load_status", "une_rt_m")

    assert len(found) == 1
    assert "status failed: HTTP 500" in found[0]


@pytest.mark.parametrize("check", ["reconciliation", "missing_periods", "value_range"])
def test_checks_pass_on_consistent_fixture(db: Connection, check: str) -> None:
    load_and_transform(db, "UNEMPLOYMENT_RATE", months("HR", 2024, "5") + months("SI", 2024, "4"))

    assert issues(db, check, "UNEMPLOYMENT_RATE") == []
