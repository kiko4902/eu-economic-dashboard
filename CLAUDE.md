# CLAUDE.md

## Project

EU Economic Dashboard answers one question: "Has life in Croatia (and the EU) become more or
less affordable since 2010?" A Python pipeline extracts Eurostat data (net earnings, HICP
inflation, house prices, unemployment, GDP per capita) for EU-27 + EU aggregate into PostgreSQL,
transforms it into a star schema, exposes analytics views, and a Power BI report sits on top.
It is a portfolio piece for a data role.

**`docs/PLAN.md` is the source of truth.** Read it before starting any phase.

## Tech stack

- Python 3.12+: pandas, requests / eurostat, SQLAlchemy, psycopg, python-dotenv, pytest, ruff
- PostgreSQL 16 in Docker (Docker Compose), Makefile
- GitHub Actions CI, Power BI Desktop for the report

## Repository structure

```
sql/init/        schema creation (raw, warehouse, analytics), run on first DB start
sql/warehouse/   DDL for dimensions and facts
sql/transform/   raw -> warehouse loads
sql/analytics/   views for Power BI
src/pipeline/    config, db, extract, transform, quality, run (entry point)
tests/           pytest tests
powerbi/         .pbix + PDF export (committed)
docs/            PLAN.md, data_sources.md, images/
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
make pipeline    # full ETL (python -m pipeline.run)
make extract     # extract only
make transform   # transform only
make test        # pytest
make lint        # ruff check + format check
```

Init scripts in `sql/init/` only run on an empty volume; use `docker compose down -v` to reset.

## Workflow

Work one phase at a time. Do not start a phase until the previous one meets its
"Done when" criteria in `docs/PLAN.md`. When a phase is done, update "Current status" below.

## Current status

- [ ] Phase 0 – Setup (in progress)
- [ ] Phase 1 – Extract
- [ ] Phase 2 – Data model
- [ ] Phase 3 – Transform
- [ ] Phase 4 – Analytics
- [ ] Phase 5 – Quality, tests, CI
- [ ] Phase 6 – Power BI
- [ ] Phase 7 – Documentation
