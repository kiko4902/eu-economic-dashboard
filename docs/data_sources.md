# Data sources

All data comes from **Eurostat** through the dissemination API. Dataset codes, dimensions and
codes below were verified against the live API on **2026-10-09**.

- **Scope:** EU-27 member states + `EU27_2020` aggregate, from 2010 to the latest period.
- **API:** SDMX 3.0, SDMX-CSV 2.0 format, e.g.
  `https://ec.europa.eu/eurostat/api/dissemination/sdmx/3.0/data/dataflow/ESTAT/une_rt_m/1.0/*?c[s_adj]=SA&c[age]=TOTAL&c[unit]=PC_ACT&c[sex]=T&c[TIME_PERIOD]=ge:2010&format=csvdata&formatVersion=2.0&compress=false`
- Non-geo dimensions are filtered on the server (by dimension name). Geo is filtered after
  download, because Eurostat rejects a whole request that contains a geo code not present in the
  dataset (e.g. `EL` in `prc_hpi_q`).
- Observation flags are kept as received (`obs_flag`); see [flag codes](#observation-flags).
- Filters are defined in `src/pipeline/config.py` (`DATASETS`).

## Summary

| Indicator (our code) | Dataset | Frequency | Unit | Raw table |
|---|---|---|---|---|
| `NET_EARNINGS` | `earn_nt_net` | annual | EUR per year | `raw.earn_nt_net` |
| `HICP_ANNUAL_RATE` | `prc_hicp_minr` (replaces `prc_hicp_manr`) | monthly | % change on same month of previous year | `raw.prc_hicp_minr` |
| `HOUSE_PRICE_INDEX` | `prc_hpi_q` | quarterly | index, 2015 = 100 | `raw.prc_hpi_q` |
| `UNEMPLOYMENT_RATE` | `une_rt_m` | monthly | % of labour force | `raw.une_rt_m` |
| `GDP_PC_PPS` | `nama_10_pc` | annual | PPS (EU27_2020) per inhabitant | `raw.nama_10_pc` |

## Datasets

### Net earnings – `earn_nt_net`

- **Title:** Annual net earnings
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/earn_nt_net/default/table?lang=en
- **Frequency / unit:** annual / EUR
- **Filters:**
  - `currency=EUR`: one common currency for comparing countries (PPS also exists; EUR is what people are paid in).
  - `estruct=NET`: net earnings (after tax and social contributions), as in the plan.
  - `ecase=P1_NCH_AW100`: single person without children earning 100% of the average wage, as in the plan.
- **Coverage:** all 28 geos, 2010–2025.
- ⚠️ **Break in series in 2024.** Eurostat's metadata says the data were estimated by the OECD
  until 2023 and by the JRC (EUROMOD) from 2024, and 2024 is flagged `b`. In the data, **every
  2024 value is about 1/12 of the 2023 value** (e.g. HR 12,601 → 1,267 → 16,892; EU27 28,324 →
  2,398 → 29,954). 2024 looks like a monthly amount. 2025 is back at an annual level but on the
  new methodology: the 2023 → 2025 change ranges from −10% (NL) to +46% (BG), so 2025 is not
  comparable with 2023. `earn_nt_netft` has the same break. Raw data is kept as received. How to
  handle it (exclude 2024, treat 2024+ as a separate series, …) is decided in Phase 3.

### Inflation (HICP) – `prc_hicp_minr`

- **Title:** Harmonised index of consumer prices (HICP) - ECOICOP ver.2 - indices and rates of change, monthly data
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_minr/default/table?lang=en
- **Frequency / unit:** monthly / annual rate of change (%)
- **Why not `prc_hicp_manr` (the plan's choice):** it is discontinued. Its title is now "HICP -
  monthly data (annual rate of change) (1997-2025)" and its last update was 2026-02-06, with
  data ending 2025-12. Eurostat moved HICP to the ECOICOP ver.2 classification in 2026 and
  publishes it in `prc_hicp_minr`, which contains back-cast history (HR from 1998, EU27 from
  2000) and is updated monthly. Over 2010–2025 the two datasets agree: for HR 180 of 192
  months are identical and the rest differ by at most ±0.1 pp (EU27: 184 of 192).
- **Filters:**
  - `unit=RCH_A`: annual rate of change (same month of previous year), the headline inflation figure.
  - `coicop18=TOTAL`: all-items HICP (the ECOICOP ver.2 equivalent of the old `CP00`).
- **Coverage:** all 28 geos, 2010-01 to latest (2026-08/09).

### House price index – `prc_hpi_q`

- **Title:** House price index - quarterly data
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/prc_hpi_q/default/table?lang=en
- **Frequency / unit:** quarterly / index, 2015 = 100
- **Filters:**
  - `purchase=TOTAL`: all dwellings (new and existing).
  - `unit=I15_Q`: index 2015 = 100, as in the plan. (`I25_Q`, 2025 = 100, also exists; `I15_Q` matches the plan's base year for cross-indicator comparison.)
- **Coverage:** 27 geos. ⚠️ **Greece (`EL`) is not in this dataset.** Greece does not report a
  house price index to Eurostat. Quality checks must treat EL as a known gap for this indicator.

### Unemployment rate – `une_rt_m`

- **Title:** Unemployment by sex and age - monthly data
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/une_rt_m/default/table?lang=en
- **Frequency / unit:** monthly / % of labour force
- **Filters:**
  - `s_adj=SA`: seasonally adjusted, as in the plan (`TC` trend-cycle is smoother but revised more).
  - `age=TOTAL`: all ages 15–74.
  - `sex=T`: total, both sexes.
  - `unit=PC_ACT`: percentage of the active population (labour force).
- **Coverage:** all 28 geos, 2010-01 to latest (2026-08).

### GDP per capita (PPS) – `nama_10_pc`

- **Title:** Gross domestic product (GDP) and main components per capita - annual data
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/nama_10_pc/default/table?lang=en
- **Frequency / unit:** annual / PPS (EU27_2020 basis) per inhabitant, current prices
- **Filters:**
  - `na_item=B1GQ`: gross domestic product at market prices.
  - `unit=CP_PPS_EU27_2020_HAB`: PPS per inhabitant. This removes price-level differences
    between countries. The alternative `PC_EU27_2020_HAB_MPPS_CP` (index, EU27 = 100) can be
    derived from it as country / EU27_2020.
- **Coverage:** all 28 geos, 2010–2025 (latest years flagged `p` provisional).

## Observation flags

Seen in the loaded data (Eurostat flag codes):

| Flag | Meaning |
|---|---|
| `b` | break in time series |
| `d` | definition differs (see metadata) |
| `e` | estimated |
| `p` | provisional |

## Licence and attribution

Eurostat data is licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
([Eurostat copyright notice](https://ec.europa.eu/eurostat/about-us/policies/copyright)).

Attribution text:

> Source: Eurostat (earn_nt_net, prc_hicp_minr, prc_hpi_q, une_rt_m, nama_10_pc), © European Union, CC BY 4.0. Data retrieved via the Eurostat dissemination API.
