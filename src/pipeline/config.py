"""Project configuration: database settings from .env and Eurostat dataset definitions."""

import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = PROJECT_ROOT / "sql"


@dataclass(frozen=True)
class DbSettings:
    host: str
    port: int
    user: str
    password: str
    name: str


def load_db_settings() -> DbSettings:
    """Read DB settings from the environment (and .env in the project root)."""
    load_dotenv(PROJECT_ROOT / ".env")
    required = ["POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"]
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError(
            f"Missing environment variables: {', '.join(missing)}. Create .env from .env.example."
        )
    return DbSettings(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        name=os.environ["POSTGRES_DB"],
    )


# --- Eurostat API ---------------------------------------------------------------------------

# SDMX 3.0 data endpoint: filters are passed by dimension name (c[unit]=...), so dataset
# definitions do not depend on the order of dimensions in Eurostat's data structure.
EUROSTAT_API_BASE = "https://ec.europa.eu/eurostat/api/dissemination/sdmx/3.0/data/dataflow/ESTAT"
EUROSTAT_DATAFLOW_VERSION = "1.0"

REQUEST_TIMEOUT = (10, 120)  # (connect, read) seconds
MAX_RETRIES = 4
BACKOFF_SECONDS = 2.0  # doubled after each failed attempt

START_YEAR = 2010

EU27_COUNTRIES = frozenset(
    "AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK".split()
)
EU_AGGREGATE = "EU27_2020"
GEO_SCOPE = EU27_COUNTRIES | {EU_AGGREGATE}


@dataclass(frozen=True)
class Dataset:
    """One Eurostat dataset loaded into raw.<code>.

    Adding a dataset: add an entry to DATASETS and a matching DDL file sql/raw/tables/<code>.sql.
    """

    code: str  # Eurostat dataset code, also the raw table name
    indicator_code: str  # our own short code, used later in warehouse.dim_indicator
    dimensions: tuple[str, ...]  # all dimension columns in the SDMX-CSV response
    filters: Mapping[str, str] = field(default_factory=dict)  # dimension -> code (server-side)

    @property
    def table(self) -> str:
        return self.code


# Choices and reasons are documented in docs/data_sources.md.
DATASETS: tuple[Dataset, ...] = (
    Dataset(
        code="earn_nt_net",
        indicator_code="NET_EARNINGS",
        dimensions=("freq", "currency", "estruct", "ecase", "geo"),
        filters={"freq": "A", "currency": "EUR", "estruct": "NET", "ecase": "P1_NCH_AW100"},
    ),
    Dataset(
        code="prc_hicp_minr",
        indicator_code="HICP_ANNUAL_RATE",
        dimensions=("freq", "unit", "coicop18", "geo"),
        filters={"freq": "M", "unit": "RCH_A", "coicop18": "TOTAL"},
    ),
    Dataset(
        code="prc_hpi_q",
        indicator_code="HOUSE_PRICE_INDEX",
        dimensions=("freq", "purchase", "unit", "geo"),
        filters={"freq": "Q", "purchase": "TOTAL", "unit": "I15_Q"},
    ),
    Dataset(
        code="une_rt_m",
        indicator_code="UNEMPLOYMENT_RATE",
        dimensions=("freq", "s_adj", "age", "unit", "sex", "geo"),
        filters={"freq": "M", "s_adj": "SA", "age": "TOTAL", "unit": "PC_ACT", "sex": "T"},
    ),
    Dataset(
        code="nama_10_pc",
        indicator_code="GDP_PC_PPS",
        dimensions=("freq", "unit", "na_item", "geo"),
        filters={"freq": "A", "unit": "CP_PPS_EU27_2020_HAB", "na_item": "B1GQ"},
    ),
)
