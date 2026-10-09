# EU Economic Dashboard

[![CI](https://github.com/kiko4902/eu-economic-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/kiko4902/eu-economic-dashboard/actions/workflows/ci.yml)

**Has life in Croatia (and the EU) become more or less affordable since 2010?**

An ETL pipeline from the Eurostat API into a PostgreSQL star schema, with a Power BI report on top.

> Work in progress. See [docs/PLAN.md](docs/PLAN.md) for the full plan.

## The question and key findings

_TODO (Phase 7)_

## Report screenshots

_TODO (Phase 6)_

## Architecture

_TODO (Phase 7)_

## Data model (ER diagram)

_TODO (Phase 7)_

## How to run

_TODO (Phase 7)_

### Updating dependencies

Versions are pinned in `uv.lock` (installed with `make install`, used by CI). To upgrade:

```
make lock
```

This runs `uv lock --upgrade` and syncs `.venv`; then run `make lint test` and commit `uv.lock`.

## Data sources and licence

Data: © European Union, Eurostat, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Datasets: `nama_10_fte`, `earn_nt_net`, `prc_hicp_minr`,
`prc_hpi_q`, `une_rt_m`, `nama_10_pc`; see [docs/data_sources.md](docs/data_sources.md) for filters and caveats.

## Tech stack and project structure

_TODO (Phase 7)_
