# CLAUDE.md

## Project

EU Economic Dashboard answers one question: "Has life in Croatia (and the EU) become more or
less affordable since 2010?" A Python pipeline extracts Eurostat data (net earnings, HICP
inflation, house prices, unemployment, GDP per capita) for EU-27 + EU aggregate into PostgreSQL,
transforms it into a star schema, exposes analytics views, and a Power BI report sits on top.
It is a portfolio piece for a data role.

**`docs/PLAN.md` is the source of truth.** Read it before starting any phase.
Final dataset choices are in `docs/data_sources.md` and supersede PLAN section 2
(HICP uses `prc_hicp_minr`, not the discontinued `prc_hicp_manr`).

## Tech stack

- Python 3.12 (pinned), dependencies locked in uv.lock (uv): pandas, requests / eurostat, SQLAlchemy, psycopg, python-dotenv, pytest, ruff
- PostgreSQL 16 in Docker (Docker Compose), Makefile
- GitHub Actions CI, Power BI Desktop for the report

## Repository structure

```
sql/init/        schema creation (raw, warehouse, analytics), run on first DB start
sql/raw/         raw table DDL (tables/, applied by extract) and load_log queries
sql/warehouse/   star schema DDL + helper functions (*.sql), seed/ upserts, queries/
seeds/           CSV seeds: dim_country, dim_indicator, dim_flag; quality_rules, known_gaps
sql/transform/   raw -> fact loads: NN_<indicator>.sql (raw filters) + steps/ (shared mapping/load)
sql/quality/     quality checks (checks/), rule setup, result tables (schema quality)
sql/analytics/   views for Power BI, NN_<view>.sql in dependency order; queries/
sql/roles/       read-only powerbi_reader role (SELECT on analytics only)
src/pipeline/    config, db, extract, warehouse, transform, analytics, quality, reconciliation, run
tests/           pytest (fixtures/ API samples, db_helpers.py, sql/); no network in tests
.github/         workflows: ci.yml (push/PR), scheduled.yml (weekly + manual)
powerbi/         .pbix + PDF export (committed)
docs/            PLAN.md, data_sources.md, findings_draft.md, SETUP_NOTES.md, images/ (er_diagram.md)
```

## Conventions

- All SQL lives in `.sql` files, never as strings inside Python.
- Transforms are idempotent: re-running gives the same result.
- Raw data is never modified in place.
- Configuration (DB credentials) comes from `.env`; only `.env.example` is committed.
- English for code, comments, commit messages and docs.
- Type hints on all functions; keep functions small and focused.
- Keep Eurostat observation flags (`p`, `e`, `b`, ...).
- Never run destructive SQL (DELETE, TRUNCATE, DROP) by hand outside a transaction that is
  rolled back, unless the user explicitly asks. Prefer testing on a copy (e.g. a separate
  scratch database) over the main database.

## Common commands

```
make up          # start PostgreSQL (waits for healthcheck)
make down        # stop PostgreSQL (volume kept)
make install     # uv sync --locked: .venv with the exact versions in uv.lock
make lock        # upgrade dependencies (uv lock --upgrade), then commit uv.lock
make db-shell    # psql inside the container
make pipeline    # full ETL: extract -> warehouse -> transform -> analytics -> quality
make extract     # extract only
make warehouse   # create star schema + populate dimensions
make transform   # load fact table from raw, then reconcile
make analytics   # create analytics views + powerbi_reader role (POWERBI_READER_PASSWORD in .env)
make quality     # all quality checks (error fails, warning logs); results in quality.*
make reconcile   # raw vs fact row counts; every difference must have a skip reason
make test        # pytest; DB tests run in a rolled-back transaction, skip without DB
                 # (REQUIRE_DB=1 makes them fail instead, as in CI)
make lint        # ruff check + format check
```

Init scripts in `sql/init/` only run on an empty volume; use `docker compose down -v` to reset.
DDL uses `CREATE ... IF NOT EXISTS` and views `CREATE OR REPLACE VIEW`: after changing a table
definition or removing/renaming view columns, reset the DB.
Use `POSTGRES_HOST=127.0.0.1` (localhost stalls ~60 s on Windows via IPv6).
Adding an indicator: config.DATASETS, seeds/dim_indicator.csv, sql/transform/NN_<code>.sql,
seeds/quality_rules.csv (and seeds/known_gaps.csv for documented gaps).

## Workflow

Work one phase at a time. Do not start a phase until the previous one meets its
"Done when" criteria in `docs/PLAN.md`. When a phase is done, update "Current status" below.

## Current status

- [x] Phase 0 – Setup
- [x] Phase 1 – Extract
- [x] Phase 2 – Data model
- [x] Phase 3 – Transform
- [x] Phase 4 – Analytics
- [x] Phase 5 – Quality, tests, CI
- [ ] Phase 6 – Power BI
- [ ] Phase 7 – Documentation
