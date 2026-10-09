"""Unit tests for parsing and downloading Eurostat SDMX-CSV (no network calls)."""

from decimal import Decimal
from pathlib import Path

import pandas as pd
import pytest
import requests

from pipeline import config
from pipeline.extract import ExtractError, build_params, fetch_csv, parse_csv

FIXTURES = Path(__file__).parent / "fixtures"
HEADER = (
    "STRUCTURE,STRUCTURE_ID,freq,s_adj,age,unit,sex,geo,TIME_PERIOD,OBS_VALUE,OBS_FLAG,CONF_STATUS"
)


def dataset(code: str) -> config.Dataset:
    return next(d for d in config.DATASETS if d.code == code)


def une_csv(*rows: str) -> str:
    return "\n".join([HEADER, *rows]) + "\n"


def une_row(geo: str = "HR", period: str = "2026-01", value: str = "4.4", flag: str = "") -> str:
    return f"dataflow,ESTAT:UNE_RT_M(1.0),M,SA,TOTAL,PC_ACT,T,{geo},{period},{value},{flag},"


# --- parse_csv ------------------------------------------------------------------------------


def test_parse_fixture_keeps_only_geo_scope() -> None:
    text = (FIXTURES / "une_rt_m_sample.csv").read_text(encoding="utf-8")
    df = parse_csv(dataset("une_rt_m"), text)

    assert set(df["geo"]) == {"HR", "EU27_2020"}  # NO (Norway) is out of scope
    assert len(df) == 8
    assert list(df.columns) == [
        "freq",
        "s_adj",
        "age",
        "unit",
        "sex",
        "geo",
        "time_period",
        "obs_value",
        "obs_flag",
        "conf_status",
    ]


def test_parse_fixture_values_are_exact_decimals() -> None:
    text = (FIXTURES / "une_rt_m_sample.csv").read_text(encoding="utf-8")
    df = parse_csv(dataset("une_rt_m"), text)

    hr_aug = df[(df["geo"] == "HR") & (df["time_period"] == "2026-08")]
    assert hr_aug["obs_value"].item() == Decimal("4.3")


def test_parse_keeps_flags_and_maps_empty_flag_to_missing() -> None:
    text = (FIXTURES / "earn_nt_net_sample.csv").read_text(encoding="utf-8")
    df = parse_csv(dataset("earn_nt_net"), text).set_index(["geo", "time_period"])

    assert df.loc[("HR", "2024"), "obs_flag"] == "b"
    assert pd.isna(df.loc[("HR", "2023"), "obs_flag"])  # stored as NULL
    assert df.loc[("HR", "2025"), "obs_value"] == Decimal("16891.93")


def test_parse_missing_value_becomes_none() -> None:
    df = parse_csv(dataset("une_rt_m"), une_csv(une_row(value="", flag="c")))

    assert df["obs_value"].item() is None
    assert df["obs_flag"].item() == "c"


def test_parse_drops_periods_before_start_year() -> None:
    df = parse_csv(dataset("une_rt_m"), une_csv(une_row(period="2009-12"), une_row()))

    assert list(df["time_period"]) == ["2026-01"]


def test_parse_rejects_response_without_rows_in_scope() -> None:
    with pytest.raises(ExtractError, match="no observations in scope"):
        parse_csv(dataset("une_rt_m"), une_csv(une_row(geo="NO")))


def test_parse_rejects_unexpected_columns() -> None:
    text = une_csv(une_row()).replace(",age,", ",age_group,")

    with pytest.raises(ExtractError, match="unexpected columns"):
        parse_csv(dataset("une_rt_m"), text)


def test_parse_rejects_duplicates() -> None:
    with pytest.raises(ExtractError, match="duplicate"):
        parse_csv(dataset("une_rt_m"), une_csv(une_row(), une_row(value="5.0")))


def test_parse_rejects_non_numeric_value() -> None:
    with pytest.raises(ExtractError, match="non-numeric"):
        parse_csv(dataset("une_rt_m"), une_csv(une_row(value="n/a")))


def test_parse_rejects_non_csv_body() -> None:
    with pytest.raises(ExtractError, match="not SDMX-CSV"):
        parse_csv(dataset("une_rt_m"), "<?xml version='1.0'?><message/>")


# --- build_params / fetch_csv ---------------------------------------------------------------


def test_build_params_filters_by_dimension_name_without_geo() -> None:
    params = build_params(dataset("une_rt_m"))

    assert params["c[s_adj]"] == "SA"
    assert params["c[TIME_PERIOD]"] == f"ge:{config.START_YEAR}"
    assert params["format"] == "csvdata"
    assert "c[geo]" not in params


class FakeResponse:
    def __init__(self, status_code: int, text: str = "") -> None:
        self.status_code = status_code
        self.text = text


class FakeSession:
    """Returns queued responses (or raises queued exceptions) in order."""

    def __init__(self, *outcomes: FakeResponse | Exception) -> None:
        self.outcomes = list(outcomes)
        self.calls = 0

    def get(self, *args: object, **kwargs: object) -> FakeResponse:
        self.calls += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome


def test_fetch_retries_transient_errors_then_succeeds() -> None:
    session = FakeSession(
        requests.ConnectionError("reset"), FakeResponse(503), FakeResponse(200, "STRUCTURE,...")
    )
    sleeps: list[float] = []

    text = fetch_csv(dataset("une_rt_m"), session, sleep=sleeps.append)  # type: ignore[arg-type]

    assert text == "STRUCTURE,..."
    assert session.calls == 3
    assert sleeps == [config.BACKOFF_SECONDS, config.BACKOFF_SECONDS * 2]


def test_fetch_does_not_retry_client_errors_and_reports_eurostat_message() -> None:
    body = "<S:Fault><faultstring>INVALID_QUERY_DIMENSION_VALUE: GEO=EL.</faultstring></S:Fault>"
    session = FakeSession(FakeResponse(400, body))

    with pytest.raises(ExtractError, match="HTTP 400.*GEO=EL"):
        fetch_csv(dataset("prc_hpi_q"), session, sleep=lambda _: None)  # type: ignore[arg-type]
    assert session.calls == 1


def test_fetch_gives_up_after_max_retries() -> None:
    session = FakeSession(*[FakeResponse(503)] * config.MAX_RETRIES)

    with pytest.raises(ExtractError, match="giving up"):
        fetch_csv(dataset("une_rt_m"), session, sleep=lambda _: None)  # type: ignore[arg-type]
    assert session.calls == config.MAX_RETRIES
