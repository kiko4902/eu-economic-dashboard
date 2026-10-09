"""Extract: download Eurostat datasets and load them into raw.<dataset> tables.

Format choice: SDMX-CSV (SDMX 3.0 endpoint, format=csvdata). It is already in long format,
one row per observation with the observation flag in its own column, so parsing is a plain
CSV read. JSON-stat would need index arithmetic over a flattened value array to rebuild the
same rows, and the `eurostat` package hides request details (timeouts, retries, errors).
"""

import io
import logging
import re
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

import pandas as pd
import requests
from sqlalchemy import Connection, Engine, MetaData, Table, insert, text

from pipeline import config
from pipeline.config import Dataset
from pipeline.db import (
    describe_error,
    ensure_schemas,
    execute_script,
    get_engine,
    read_sql,
    sql_files,
)
from pipeline.logs import configure_logging

logger = logging.getLogger(__name__)

RETRYABLE_STATUS = {429, 500, 502, 503, 504}
MISSING_VALUES = {"", ":"}
SDMX_COLUMNS = {
    "TIME_PERIOD": "time_period",
    "OBS_VALUE": "obs_value",
    "OBS_FLAG": "obs_flag",
    "CONF_STATUS": "conf_status",
}
DROPPED_COLUMNS = ["STRUCTURE", "STRUCTURE_ID", "STRUCTURE_NAME", "ACTION"]


class ExtractError(Exception):
    """A dataset could not be downloaded or parsed."""


@dataclass(frozen=True)
class LoadResult:
    dataset: str
    load_id: int
    rows_loaded: int
    status: str
    error_message: str | None = None


# --- Download -------------------------------------------------------------------------------


def build_url(dataset: Dataset) -> str:
    return f"{config.EUROSTAT_API_BASE}/{dataset.code}/{config.EUROSTAT_DATAFLOW_VERSION}/*"


def build_params(dataset: Dataset) -> dict[str, str]:
    """Query parameters: server-side dimension filters, start period and CSV format.

    Geo is not filtered server-side: Eurostat rejects the whole request if a geo code is not
    valid for a dataset (e.g. EL in prc_hpi_q), so countries are filtered after parsing.
    """
    params = {f"c[{dim}]": code for dim, code in dataset.filters.items()}
    params["c[TIME_PERIOD]"] = f"ge:{config.START_YEAR}"
    params.update({"format": "csvdata", "formatVersion": "2.0", "compress": "false"})
    return params


def fetch_csv(
    dataset: Dataset,
    session: requests.Session | None = None,
    sleep: Callable[[float], None] = time.sleep,
) -> str:
    """Download a dataset as SDMX-CSV text, retrying transient failures with backoff."""
    session = session or requests.Session()
    url, params = build_url(dataset), build_params(dataset)
    delay = config.BACKOFF_SECONDS
    for attempt in range(1, config.MAX_RETRIES + 1):
        try:
            response = session.get(url, params=params, timeout=config.REQUEST_TIMEOUT)
        except (requests.ConnectionError, requests.Timeout) as exc:
            reason = f"{type(exc).__name__}: {exc}"
        else:
            if response.status_code == 200:
                return response.text
            if response.status_code not in RETRYABLE_STATUS:
                raise ExtractError(
                    f"{dataset.code}: HTTP {response.status_code} from Eurostat: "
                    f"{_eurostat_error(response.text)}"
                )
            reason = f"HTTP {response.status_code}"
        if attempt == config.MAX_RETRIES:
            raise ExtractError(
                f"{dataset.code}: giving up after {attempt} attempts (last error: {reason})"
            )
        logger.warning(
            "%s: attempt %d/%d failed (%s), retrying in %.0fs",
            dataset.code,
            attempt,
            config.MAX_RETRIES,
            reason,
            delay,
        )
        sleep(delay)
        delay *= 2
    raise AssertionError("unreachable")


def _eurostat_error(body: str) -> str:
    """Extract the faultstring from Eurostat's XML error body, or a short snippet."""
    match = re.search(r"<faultstring>(.*?)</faultstring>", body, re.S)
    return (match.group(1) if match else body[:300]).strip()


# --- Parse ----------------------------------------------------------------------------------


def parse_csv(dataset: Dataset, csv_text: str) -> pd.DataFrame:
    """Parse SDMX-CSV into the raw table layout, filtered to the geo and time scope."""
    if not csv_text.startswith("STRUCTURE"):
        raise ExtractError(
            f"{dataset.code}: response is not SDMX-CSV (starts with {csv_text[:80]!r})"
        )
    df = pd.read_csv(io.StringIO(csv_text), dtype=str, keep_default_na=False)
    df = df.drop(columns=[c for c in DROPPED_COLUMNS if c in df.columns])
    df = df.rename(columns=SDMX_COLUMNS)
    if "conf_status" not in df.columns:  # optional attribute, not sent by every dataset
        df["conf_status"] = ""
    _check_columns(dataset, df)

    df = df[df["geo"].isin(config.GEO_SCOPE)]
    df = df[df["time_period"].str[:4].astype(int) >= config.START_YEAR]
    if df.empty:  # never replace a loaded dataset with nothing
        raise ExtractError(f"{dataset.code}: no observations in scope (geo/time filters)")
    df = df.assign(
        obs_value=df["obs_value"].map(lambda v: _to_decimal(dataset, v)),
        obs_flag=df["obs_flag"].replace("", None),
        conf_status=df["conf_status"].replace("", None),
    )
    _check_unique(dataset, df)
    columns = [*dataset.dimensions, "time_period", "obs_value", "obs_flag", "conf_status"]
    return df[columns].reset_index(drop=True)


def _check_columns(dataset: Dataset, df: pd.DataFrame) -> None:
    expected = {*dataset.dimensions, *SDMX_COLUMNS.values()}
    actual = set(df.columns)
    if expected != actual:
        raise ExtractError(
            f"{dataset.code}: unexpected columns (dataset restructured?). "
            f"Missing: {sorted(expected - actual)}, unexpected: {sorted(actual - expected)}"
        )


def _check_unique(dataset: Dataset, df: pd.DataFrame) -> None:
    key = [*dataset.dimensions, "time_period"]
    duplicates = df[df.duplicated(key, keep=False)]
    if not duplicates.empty:
        raise ExtractError(
            f"{dataset.code}: {len(duplicates)} duplicate observations, e.g. "
            f"{duplicates[key].iloc[0].to_dict()}"
        )


def _to_decimal(dataset: Dataset, value: str) -> Decimal | None:
    if value.strip() in MISSING_VALUES:
        return None
    try:
        return Decimal(value)
    except InvalidOperation:
        raise ExtractError(f"{dataset.code}: non-numeric OBS_VALUE {value!r}") from None


# --- Load -----------------------------------------------------------------------------------


def ensure_raw_tables(engine: Engine) -> None:
    """Create raw.load_log and the raw dataset tables if they do not exist."""
    with engine.begin() as conn:
        ensure_schemas(conn)
        for path in sql_files("raw/tables"):
            execute_script(conn, path)


def replace_dataset(conn: Connection, dataset: Dataset, df: pd.DataFrame, load_id: int) -> int:
    """Delete the dataset's rows and insert the new ones (caller owns the transaction)."""
    conn.execute(text(read_sql("raw/delete_dataset.sql", table=dataset.table)))
    # Reflect the table so column types come from the DDL (obs_value stays an exact numeric).
    table = Table(dataset.table, MetaData(), schema="raw", autoload_with=conn)
    records = df.assign(load_id=load_id).astype(object)
    records = records.where(records.notna(), None)  # NaN -> NULL
    if not records.empty:
        conn.execute(insert(table), records.to_dict("records"))
    return len(records)


def _start_log(engine: Engine, dataset: Dataset) -> int:
    with engine.begin() as conn:
        result = conn.execute(text(read_sql("raw/load_log_start.sql")), {"dataset": dataset.code})
        return result.scalar_one()


def _finish_log(engine: Engine, result: LoadResult) -> None:
    with engine.begin() as conn:
        conn.execute(
            text(read_sql("raw/load_log_finish.sql")),
            {
                "load_id": result.load_id,
                "status": result.status,
                "rows_loaded": result.rows_loaded,
                "error_message": result.error_message,
            },
        )


def extract_dataset(engine: Engine, dataset: Dataset, session: requests.Session) -> LoadResult:
    """Download, parse and load one dataset, recording the run in raw.load_log."""
    load_id = _start_log(engine, dataset)
    logger.info("%s: extracting (load_id=%d)", dataset.code, load_id)
    try:
        df = parse_csv(dataset, fetch_csv(dataset, session))
        with engine.begin() as conn:
            rows = replace_dataset(conn, dataset, df, load_id)
        result = LoadResult(dataset.code, load_id, rows, "success")
        logger.info("%s: loaded %d rows", dataset.code, rows)
    except Exception as exc:  # noqa: BLE001 - every failure must be logged to raw.load_log
        result = LoadResult(dataset.code, load_id, 0, "failed", describe_error(exc))
        logger.error("%s: failed: %s", dataset.code, result.error_message)
    _finish_log(engine, result)
    return result


def run_extract(datasets: tuple[Dataset, ...] = config.DATASETS) -> list[LoadResult]:
    """Extract all datasets. A failing dataset does not stop the others."""
    engine = get_engine()
    ensure_raw_tables(engine)
    with requests.Session() as session:
        return [extract_dataset(engine, dataset, session) for dataset in datasets]


def main() -> int:
    configure_logging()
    results = run_extract()
    failed = [r.dataset for r in results if r.status != "success"]
    if failed:
        logger.error("Extract finished with failures: %s", ", ".join(failed))
        return 1
    logger.info("Extract finished: %d datasets loaded", len(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
