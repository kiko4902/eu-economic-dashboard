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

- Python 3.12 (pinned): pandas, requests / eurostat, SQLAlchemy, psycopg, python-dotenv, pytest, ruff
- PostgreSQL 16 in Docker (Docker Compose), Makefile
- GitHub Actions CI, Power BI Desktop for the report

## Repository structure

```
sql/init/        schema creation (raw, warehouse, analytics), run on first DB start
sql/raw/         raw table DDL (tables/, applied by extract) and load_log queries
sql/warehouse/   star schema DDL (*.sql), seed/ upserts, queries/
seeds/           CSV seed data for dim_country, dim_indicator, dim_flag
sql/transform/   raw -> warehouse loads
sql/analytics/   views for Power BI
src/pipeline/    config, db, extract, warehouse, transform, quality, run (entry point)
tests/           pytest tests (fixtures/ holds saved API samples; no network in tests)
powerbi/         .pbix + PDF export (committed)
docs/            PLAN.md, data_sources.md, SETUP_NOTES.md, images/ (er_diagram.md)
```

## Conventions

- All SQL lives in `.sql` files, never as strings inside Python.
- Transforms are idempotent: re-running gives the same result.
- Raw data is never modified in place.
- Configuration (DB credentials) comes from `.env`; only `.env.example` is committed.
- English for code, comments, commit messages and docs.
- Type hints on all functions; keep functions small and focused.
- Keep Eurostat observation flags (`p`, `e`, `b`, ...).

## Common commands

```
make up          # start PostgreSQL (waits for healthcheck)
make down        # stop PostgreSQL (volume kept)
make install     # create .venv, install package + dev deps
make db-shell    # psql inside the container
make pipeline    # full ETL: extract -> warehouse (python -m pipeline.run)
make extract     # extract only
make warehouse   # create star schema + populate dimensions
make transform   # transform only
make test        # pytest
make lint        # ruff check + format check
```

Init scripts in `sql/init/` only run on an empty volume; use `docker compose down -v` to reset.
DDL uses `CREATE ... IF NOT EXISTS`: after changing a table definition, reset the DB.
Use `POSTGRES_HOST=127.0.0.1` (localhost stalls ~60 s on Windows via IPv6).

## Workflow

Work one phase at a time. Do not start a phase until the previous one meets its
"Done when" criteria in `docs/PLAN.md`. When a phase is done, update "Current status" below.

## Current status

- [x] Phase 0 – Setup
- [x] Phase 1 – Extract
- [x] Phase 2 – Data model
- [ ] Phase 3 – Transform
- [ ] Phase 4 – Analytics
- [ ] Phase 5 – Quality, tests, CI
- [ ] Phase 6 – Power BI
- [ ] Phase 7 – Documentation
