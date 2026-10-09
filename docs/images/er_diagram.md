# Warehouse ER diagram

Star schema in the `warehouse` schema (DDL in `sql/warehouse/`). GitHub renders the Mermaid
diagram below.

```mermaid
erDiagram
    dim_country ||--o{ fact_observation : "country_key"
    dim_time ||--o{ fact_observation : "time_key"
    dim_indicator ||--o{ fact_observation : "indicator_key, frequency"
    dim_flag ||--o{ fact_observation : "flag_key"

    dim_country {
        smallint country_key PK "surrogate, identity"
        text country_code UK "Eurostat geo code, e.g. HR, EL, EU27_2020"
        text country_name
        char2 iso_alpha2 UK "ISO 3166-1 alpha-2 for maps (EL -> GR), NULL for aggregates"
        boolean is_eu_member
        smallint euro_adoption_year "NULL = not in euro area (ECB)"
        text region "UN M49: Northern / Western / Southern / Eastern Europe"
        boolean is_aggregate
    }

    dim_time {
        integer time_key PK "YYYYMMDD, first day of month"
        date period_date UK
        smallint year
        smallint quarter
        smallint month
        text month_name
        text period_label UK "YYYY-MM"
        text quarter_label "YYYY-Qn"
    }

    dim_indicator {
        smallint indicator_key PK "surrogate, identity"
        text indicator_code UK "e.g. WAGE_NAC"
        text name
        text unit
        char1 frequency "A / Q / M, UK with indicator_key"
        text source_dataset "Eurostat dataset code"
        text source_filters
        text description
        text notes "breaks, known gaps"
        smallint valid_from_year "NULL = from 2010"
        smallint valid_to_year "NULL = latest, 2023 for NET_EARNINGS"
    }

    dim_flag {
        smallint flag_key PK "surrogate, identity"
        text flag_code UK "Eurostat OBS_FLAG, '' = no flag"
        text description
        boolean is_break "generated"
        boolean is_estimated "generated"
        boolean is_provisional "generated"
    }

    fact_observation {
        smallint country_key PK,FK
        integer time_key PK,FK
        smallint indicator_key PK,FK
        smallint flag_key FK
        char1 frequency FK "must equal dim_indicator.frequency"
        numeric value
    }
```

**Grain:** one row per country × period × indicator. Annual and quarterly observations use
the `time_key` of the first month of their period (2024 → 20240101, 2024-Q2 → 20240401).
