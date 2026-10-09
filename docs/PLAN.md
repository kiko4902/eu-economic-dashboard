# Project Plan: EU Economic Dashboard (Eurostat → PostgreSQL → Power BI)

> This document is the source of truth for the project. Read it before starting any phase.
> Work phase by phase. Do not start a later phase until the current one meets its "Done when" criteria.

## 1. Goal

Answer one clear question with data:

**"Has life in Croatia (and the EU) become more or less affordable since 2010?"**

Compare wages, inflation, house prices and unemployment across EU countries, with a focus on Croatia vs the EU average.

The project is a portfolio piece for a data role. It must demonstrate:
- building a reproducible ETL pipeline from a public API
- relational data modelling (star schema) in PostgreSQL
- analytical SQL (window functions, views)
- data quality checks and tests
- a Power BI report on top of the warehouse
- DevOps practice (Docker, Makefile, CI)

## 2. Data sources (Eurostat)

| Indicator | Dataset code | Frequency | Notes |
|---|---|---|---|
| Average full-time adjusted salary (primary wage indicator, added in Phase 1) | `nama_10_fte` | annual | two indicators: `WAGE_NAC` (national currency, basis for real wage growth) and `WAGE_EUR` (cross-country levels); Netherlands not published |
| Net earnings (secondary, used up to 2023) | `earn_nt_net` | annual | single person without children, 100% of average earnings, EUR; series break from 2024 |
| Inflation (HICP) | `prc_hicp_minr` (replaces discontinued `prc_hicp_manr`) | monthly | all-items (`TOTAL`); two indicators: `HICP_INDEX` (index 2025 = 100, basis for annual inflation) and `HICP_ANNUAL_RATE` (annual rate of change) |
| House price index | `prc_hpi_q` | quarterly | total, index 2015=100 |
| Unemployment rate | `une_rt_m` | monthly | seasonally adjusted, total, % of labour force |
| GDP per capita (PPS) | `nama_10_pc` | annual | |

- Scope: EU-27 countries + EU aggregate (`EU27_2020`), from 2010 to latest available.
- Dataset codes and filter dimensions must be verified against the live API in Phase 1 (Eurostat occasionally renames or restructures datasets). Record the final choices in `docs/data_sources.md`.
- Keep Eurostat observation flags (`p` provisional, `e` estimated, `b` break in series, etc.).

## 3. Tech stack

- Python 3.12: `pandas`, `requests` and/or the `eurostat` package, `SQLAlchemy`, `psycopg`, `python-dotenv`, `pytest`
- PostgreSQL 16 in Docker
- Docker Compose, Makefile
- GitHub Actions for CI
- Power BI Desktop (Windows only) for the report
- Code, comments, commit messages and README in English

## 4. Architecture

```
Eurostat API
   │  extract (Python)
   ▼
raw schema         – data exactly as received, one table per dataset, plus load metadata
   │  transform (SQL files, run by Python)
   ▼
warehouse schema   – star schema (dimensions + fact table)
   │
   ▼
analytics schema   – views used by Power BI
```

Rules:
- Raw data is never modified in place. Transforms are idempotent (re-running gives the same result).
- All SQL lives in `.sql` files, not as strings inside Python.
- Configuration (DB credentials) comes from `.env`; `.env.example` is committed, `.env` is not.

Transform (raw → `fact_observation`, Phase 3):
- One file per indicator, `sql/transform/NN_<indicator>.sql`, selects the indicator's raw rows
  with the filters from `docs/data_sources.md` into a staging table. Shared steps in
  `sql/transform/steps/` do the rest, in one transaction per indicator:
  - periods `2024` / `2024-Q1` / `2024-01` → `dim_time` key of the first day of the period
    (`warehouse.period_start_date()`)
  - geo → `dim_country.country_code` (Eurostat codes, `EL` for Greece)
  - flag → `dim_flag` via `warehouse.normalize_flag()` (combined flags like `b,p` → `bp`)
  - rows are skipped, and counted per reason, for: `null_value` (no value),
    `out_of_scope` (period outside `dim_time`), `outside_validity` (year outside
    `dim_indicator.valid_from_year` / `valid_to_year`, e.g. `NET_EARNINGS` after 2023)
  - unknown geo, unknown flag, unparseable period or a period of the wrong frequency fail the
    indicator loudly; nothing is dropped silently
  - load: insert new rows, update changed ones, delete rows that left the source; unchanged
    rows are not touched
- Reconciliation (`quality.py`, `make reconcile`, also run by `make transform` / `make pipeline`):
  per indicator, raw rows = fact rows + skipped rows; per dataset, raw rows = rows used by its
  indicators + rows not used. Any unexplained difference fails.

## 5. Repository structure

```
eu-economic-dashboard/
├── CLAUDE.md
├── README.md
├── Makefile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── pyproject.toml            # or requirements.txt
├── docs/
│   ├── PLAN.md               # this file
│   ├── data_sources.md
│   └── images/               # architecture + ER diagrams, report screenshots
├── sql/
│   ├── init/                 # schema creation, run on DB start
│   ├── warehouse/            # DDL for dimensions and facts
│   ├── transform/            # raw → warehouse: one file per indicator + steps/
│   ├── quality/              # quality checks, rule setup, result tables
│   ├── roles/                # read-only Power BI role
│   └── analytics/            # views, one file per view
├── src/
│   └── pipeline/
│       ├── config.py
│       ├── db.py
│       ├── extract.py
│       ├── transform.py
│       ├── quality.py
│       └── run.py            # entry point: python -m pipeline.run
├── tests/
├── powerbi/
│   ├── eu_dashboard.pbix
│   └── eu_dashboard.pdf
└── .github/workflows/ci.yml
```

## 6. Data model (warehouse schema)

DDL in `sql/warehouse/`, seed data in `seeds/`, ER diagram in `docs/images/er_diagram.md`.
Every table and column has a `COMMENT`.

**dim_country** (seeded from `seeds/dim_country.csv`)
- country_key (PK, surrogate), country_code (Eurostat geo code, unique), country_name, iso_alpha2 (ISO code for maps; Greece = GR, Eurostat uses EL), is_eu_member (bool), euro_adoption_year (nullable int, verified against the ECB; e.g. HR 2023, BG 2026; NULL = not in the euro area), region (UN M49 geoscheme: Northern / Western / Southern / Eastern Europe; Cyprus mapped to Southern Europe), is_aggregate (bool, true for EU27_2020)
- CHECK: aggregates have no region, ISO code, membership or euro year

**dim_time** (generated in SQL with `generate_series`)
- time_key (PK, e.g. 20240101), period_date (first day of period), year, quarter, month, month_name, period_label (YYYY-MM), quarter_label (YYYY-Qn)
- One row per month from 2010-01 to December of the current year; annual and quarterly observations map to the first day of their period. The fact table stores the frequency.

**dim_indicator** (seeded from `seeds/dim_indicator.csv`; one row per indicator)
- indicator_key (PK), indicator_code (unique, our own short code e.g. `WAGE_NAC`), name, unit, frequency (A/Q/M), source_dataset (Eurostat code), source_filters, description, notes (series breaks, known gaps), valid_from_year / valid_to_year (nullable; the fact load only keeps years in this range, e.g. `NET_EARNINGS` valid_to_year = 2023)

**dim_flag** (seeded from `seeds/dim_flag.csv`)
- flag_key (PK), flag_code (official Eurostat OBS_FLAG codelist incl. combinations such as `bp`; empty string = no flag), description, is_break / is_estimated / is_provisional (generated)

**fact_observation**
- country_key, time_key, indicator_key (FKs), flag_key (FK), frequency, value (numeric, not null)
- Primary key on (country_key, time_key, indicator_key)
- Composite FK (indicator_key, frequency) → dim_indicator, so the frequency always matches the indicator
- Indexes on the FK columns used for filtering

## 7. Analytics layer (views in `analytics` schema)

Plain views, one file per view in `sql/analytics/NN_<view>.sql`, created in dependency order by
`analytics.py` (`make analytics`). Readable snake_case columns with `COMMENT`s for Power BI.

Rules for all annual views:
- **Complete years only**: 12 monthly / 4 quarterly / 1 annual observation. Partial years
  (e.g. the current year) are excluded, never averaged.
- **Flags carried through**: `has_provisional`, `has_estimated`, `has_break` are true if any
  underlying observation (including the previous year or the base year, where used) has that flag.

Views:
- `v_observations` – flat join of fact + all dimensions (main Power BI source)
- `v_annual_summary` – all indicators at annual grain (complete years): annual indicators as
  reported; unemployment, house prices and the HICP index as annual averages; plus derived
  `HICP_INFLATION` = annual average HICP index / previous year's − 1 (Eurostat's method; the
  average of monthly annual rates is not used). Starts in 2011 because it needs two years.
- `v_yoy_change` – change on the previous year per country and indicator (`LAG`); absolute change,
  and % change except for indicators that are rates
- `v_real_wage_growth` – real wage growth per country/year, computed as `(1 + nominal wage growth) / (1 + annual inflation) − 1`, not as a simple difference:
  - nominal wage growth: year-over-year change of `WAGE_NAC` (national currency, so no exchange-rate effects)
  - annual inflation: `HICP_INFLATION`; this reproduces Eurostat's official annual average rate (`prc_hicp_ainr`)
  - `real_wage_index_2010`: real growth chained from 2010 = 100 (NULL after a gap)
- `v_index_base_2015` – HICP index, house prices, wages (NAC and EUR), net earnings and GDP per
  capita rebased to 2015 = 100 (value / 2015 value) for cross-indicator charts
- `v_housing_affordability` – house price index vs `WAGE_NAC` index, both 2015 = 100 and both in
  national-currency terms, plus their ratio (> 100 = housing less affordable relative to wages)
- `v_gdp_relative_to_eu` – GDP per capita in PPS, EU27_2020 = 100
- `v_country_rank` – rank of the EU-27 member states (aggregate excluded) per indicator and
  year, 1 = best, direction per indicator (higher is better for wages in EUR, net earnings,
  GDP per capita and real wage growth; lower for unemployment, inflation and house prices
  relative to wages). `WAGE_NAC` and the index levels are not ranked (not comparable across
  countries).

Access: Power BI connects as the read-only role `powerbi_reader` (password `POWERBI_READER_PASSWORD`
in `.env`): `SELECT` on `analytics` only, no access to `raw` or `warehouse`, read-only sessions.

## 8. Data quality

Implemented in `quality.py` (`make quality`, also the last step of `make pipeline`). Every check
has a severity: **error** fails the run (and the pipeline / CI), **warning** is only logged.
Results are written per run to `quality.check_run` and `quality.check_result`.

| Check | Severity | What it verifies |
|---|---|---|
| `load_status` | error | the latest extract of every dataset succeeded (`raw.load_log`) |
| `reconciliation` | error | raw rows = fact rows + rows skipped for a documented reason |
| `completeness` | error | every EU-27 country + EU27_2020 has every indicator, from its start year |
| `missing_periods` | error | no missing periods inside a country's series |
| `value_range` | error | values within plausible ranges (e.g. unemployment 0–40 %, annual inflation −10 to +30 %) |
| `known_gaps_current` | warning | documented known gaps still match the data (flags stale exceptions) |
| `freshness` | warning | latest period per indicator not older than expected |

- Exceptions live in one place, `seeds/known_gaps.csv` (Greece house prices, Netherlands wages,
  net earnings start years and Cyprus 2015–2016); ranges and freshness limits in
  `seeds/quality_rules.csv`. The checks contain no hard-coded countries or indicators.
- Duplicate (country, period, indicator) rows are impossible by the fact table's primary key.

## 9. Power BI report

Connect to PostgreSQL (`analytics` schema). Four pages:
1. **Overview** – KPI cards for Croatia vs EU (latest values + change since 2010), 3–4 key findings as text
2. **Croatia vs EU** – line charts over time for all indicators
3. **Country comparison** – map of Europe, ranking table, year slicer
4. **Housing** – house prices vs earnings, affordability over time

DAX measures: latest value, YoY %, change since base year, real wage growth.
Synced slicers for country and period across pages. Consistent colour for Croatia and EU across all visuals.

Export: `.pbix` and PDF committed in `powerbi/`, screenshots in `docs/images/`.
"Publish to web" requires a work/school Microsoft account; if not available, screenshots + PDF are enough.

## 10. DevOps

- `docker compose up -d` starts PostgreSQL with schemas created by `sql/init/`
- Makefile targets: `up`, `down`, `install`, `pipeline` (full ETL), `extract`, `warehouse`, `transform`, `reconcile`, `analytics`, `quality`, `test`, `lint`, `db-shell`
- GitHub Actions (`.github/workflows/`):
  - `ci.yml` on push and pull request: job 1 lint + unit tests; job 2 with a Postgres 16 service
    container runs the full pipeline against the live Eurostat API, then all tests with
    `REQUIRE_DB=1` (database tests fail instead of skipping) and the quality checks. pip cache.
  - `scheduled.yml` weekly (Monday 05:00 UTC) + manual trigger: full pipeline and quality checks
    to detect upstream changes (renamed datasets, new gaps); logs kept as an artifact.
- The pipeline creates its schemas itself (`sql/init`), so it runs on any empty Postgres.
- Optional later: hosted Postgres (e.g. Neon free tier) for a refreshed Power BI source

## 11. README must contain

1. The question and 3–4 key findings with concrete numbers
2. Report screenshots
3. Architecture diagram
4. ER diagram of the warehouse
5. How to run it (3 commands)
6. Data sources and licence (Eurostat, CC BY 4.0) with attribution
7. Tech stack and project structure

## 12. Phases

### Phase 0 – Setup
Repo structure, `CLAUDE.md`, Docker Compose with PostgreSQL, `sql/init` creating `raw`, `warehouse`, `analytics` schemas, Makefile, dependency file, `.env.example`, `.gitignore`, README skeleton, git init.
**Done when:** `make up` starts the DB, `make db-shell` connects, the three schemas exist, `make install` works.

### Phase 1 – Extract
Verify dataset codes and filters against the live API, document them in `docs/data_sources.md`. Write `extract.py` that downloads each dataset (filtered to scope) and loads it into `raw` tables with load metadata, and logs to `raw.load_log`.
**Done when:** `make extract` loads all 5 datasets; row counts are logged; re-running replaces data without duplicates.

### Phase 2 – Data model
DDL for dimensions and fact table in `sql/warehouse/`. Populate `dim_country`, `dim_time`, `dim_indicator`, `dim_flag`.
**Done when:** all tables exist with PKs, FKs, unique constraints and indexes; dimensions are populated.

### Phase 3 – Transform
SQL in `sql/transform/` loading `fact_observation` from raw tables; `transform.py` runs the files in order. `run.py` runs extract + transform end to end.
**Done when:** `make pipeline` runs from an empty DB to a full warehouse; re-running is idempotent.

### Phase 4 – Analytics
Views from section 7.
**Done when:** every view returns sensible results; spot-check a few values against the Eurostat website.

### Phase 5 – Quality, tests, CI
Checks from section 8, pytest tests, ruff, GitHub Actions workflow.
**Done when:** `make test` and `make lint` pass locally and CI is green.

### Phase 6 – Power BI
Report from section 9 (built manually in Power BI Desktop; Claude Code can help with DAX measures and checking the views).
**Done when:** 4 pages finished, `.pbix` + PDF + screenshots committed.

### Phase 7 – Documentation
Diagrams, findings, final README.
**Done when:** someone can understand the project in 2 minutes from the README and run it in 3 commands.
