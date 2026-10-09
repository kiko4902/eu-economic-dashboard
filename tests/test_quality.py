"""Tests for the raw -> fact reconciliation logic (no database needed)."""

from pipeline.quality import DatasetBalance, Reconciliation, format_reconciliation, problems

SKIPPED = {"null_value": 1, "out_of_scope": 0, "outside_validity": 56}


def row(fact_rows: int) -> Reconciliation:
    return Reconciliation("earn_nt_net", "NET_EARNINGS", 437, SKIPPED, fact_rows)


def test_differences_explained_by_skip_reasons_pass() -> None:
    rows, balances = [row(380)], [DatasetBalance("earn_nt_net", 437, 437)]

    assert rows[0].expected_fact_rows == 380
    assert problems(rows, balances) == []
    assert "NET_EARNINGS" in format_reconciliation(rows, balances)


def test_unexplained_difference_fails() -> None:
    found = problems([row(379)], [DatasetBalance("earn_nt_net", 437, 437)])

    assert found == ["NET_EARNINGS: -1 fact rows not explained by skip reasons"]


def test_overlapping_indicator_filters_fail() -> None:
    found = problems([row(380)], [DatasetBalance("earn_nt_net", 437, 874)])

    assert found == ["earn_nt_net: indicators read 874 rows but raw has 437 (overlap)"]
