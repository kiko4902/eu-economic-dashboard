# Architecture

Data flow from the Eurostat API to the Power BI report. GitHub renders the Mermaid diagram
below. `make pipeline` (`python -m pipeline.run`) runs the steps in order.

```mermaid
flowchart LR
    api["Eurostat API<br/>6 datasets, EU-27 + EU27_2020"]

    subgraph pg["PostgreSQL 16 (Docker)"]
        direction LR
        raw["<b>raw</b><br/>one table per dataset,<br/>as received + raw.load_log"]
        wh["<b>warehouse</b><br/>star schema:<br/>fact_observation + 4 dimensions"]
        an["<b>analytics</b><br/>13 views: annual summary,<br/>real wages, housing, ranks, BI dimensions"]
        q["<b>quality</b><br/>check_run, check_result,<br/>rules, known gaps"]
    end

    pbi["Power BI report<br/>5 pages, Import mode<br/>(read-only powerbi_reader)"]

    api -- "extract.py" --> raw
    raw -- "transform.py<br/>(sql/transform/)" --> wh
    wh -- "analytics.py<br/>(sql/analytics/)" --> an
    an --> pbi

    raw -. "reconciliation:<br/>raw = fact + skipped" .-> q
    wh -. "quality.py: 7 checks<br/>(error / warning)" .-> q
    q -. "v_quality_latest,<br/>v_known_gaps" .-> an

    seeds[("seeds/*.csv<br/>dimensions, rules,<br/>known gaps")] -- "warehouse.py" --> wh
    seeds --> q

    subgraph gha["GitHub Actions"]
        ci["ci.yml (push / PR):<br/>lint + unit tests;<br/>full pipeline on Postgres service,<br/>DB tests, quality checks"]
        sched["scheduled.yml<br/>(Mondays 05:00 UTC):<br/>full pipeline + quality checks"]
    end
    gha -. "runs against<br/>the live API" .-> api
```

| Layer | What it holds | Code |
|---|---|---|
| `raw` | Eurostat data exactly as received, one table per dataset, plus `load_log` (row counts, status). Never modified in place; a re-extract replaces a dataset. | `src/pipeline/extract.py`, `sql/raw/` |
| `warehouse` | Star schema: `fact_observation` (country × period × indicator) with `dim_country`, `dim_time`, `dim_indicator`, `dim_flag`. Loads are idempotent; skipped rows are counted per reason. | `src/pipeline/warehouse.py`, `transform.py`, `sql/warehouse/`, `sql/transform/` |
| `analytics` | Views for Power BI: annual summary, YoY change, real wage growth, 2015 = 100 indices, housing affordability, GDP vs EU, country ranks, BI dimensions, latest quality results. | `src/pipeline/analytics.py`, `sql/analytics/` |
| `quality` | Results of every quality run, plus the rules and documented known gaps from `seeds/`. | `src/pipeline/quality.py`, `reconciliation.py`, `sql/quality/` |
| Power BI | Imports the `analytics` views as the read-only `powerbi_reader` role. | `powerbi/` |

ER diagram of the warehouse: [er_diagram.md](er_diagram.md).
