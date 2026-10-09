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
| `WAGE_NAC` (**primary wage indicator**, basis for real wage growth) | `nama_10_fte` | annual | national currency per employee per year | `raw.nama_10_fte` |
| `WAGE_EUR` (wage levels across countries) | `nama_10_fte` | annual | EUR per employee per year | `raw.nama_10_fte` |
| `NET_EARNINGS` (secondary, **2010–2023 only**) | `earn_nt_net` | annual | EUR per year | `raw.earn_nt_net` |
| `HICP_INDEX` (basis for annual inflation) | `prc_hicp_minr` (replaces `prc_hicp_manr`) | monthly | index, 2025 = 100 | `raw.prc_hicp_minr` |
| `HICP_ANNUAL_RATE` | `prc_hicp_minr` | monthly | % change on same month of previous year | `raw.prc_hicp_minr` |
| `HOUSE_PRICE_INDEX` | `prc_hpi_q` | quarterly | index, 2015 = 100 | `raw.prc_hpi_q` |
| `UNEMPLOYMENT_RATE` | `une_rt_m` | monthly | % of labour force | `raw.une_rt_m` |
| `GDP_PC_PPS` | `nama_10_pc` | annual | PPS (EU27_2020) per inhabitant | `raw.nama_10_pc` |

Known gaps (expected, quality checks must not fail on them; the checks read them from
`seeds/known_gaps.csv`):
- **Greece** has no house price index (`prc_hpi_q`).
- The **Netherlands** has no full-time adjusted salary (`nama_10_fte`).
- **Net earnings** (`earn_nt_net`) start in **2013** for Croatia and the EU27_2020 aggregate, and in
  **2014** for Cyprus (other countries from 2010); Cyprus also has no data for 2015 and 2016.

## Datasets

### Average full-time adjusted salary – `nama_10_fte` (primary wage indicator)

- **Title:** Average full time adjusted salary per employee
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/nama_10_fte/default/table?lang=en
- **Metadata:** https://ec.europa.eu/eurostat/cache/metadata/en/nama_10_fte_esms.htm
- **Definition:** gross wages and salaries (national accounts, ESA D.11) / number of employees,
  adjusted to full-time equivalents with an LFS-based FTE ratio: `D11 / SAL * FTE_R`. Gross
  (before income tax and employee social contributions), current prices.
- **Frequency / unit:** annual / EUR and national currency (`NAC`).
- **Filters:**
  - `freq=A`: the only frequency.
  - `unit=NAC,EUR`: both units are extracted and split into **two indicators**:
    - **`WAGE_NAC`** (`unit=NAC`): basis for nominal and **real wage growth**. Growth in EUR
      would include exchange-rate movements for non-euro countries (PL, HU, CZ, RO, SE, DK,
      and BG before 2026). NAC levels are in different currencies, so use them for growth
      only. Countries that adopted the euro are shown in euro for all years, converted at
      the irrevocable rate (HR: NAC equals EUR from 2023; 2010 is 14,099 NAC vs 14,573 EUR
      at the market rate). BG is still in lev in the current release.
    - **`WAGE_EUR`** (`unit=EUR`): for **comparing wage levels** between countries.
- **Coverage:** 26 member states + `EU27_2020`, 2010–2024 (released annually in autumn,
  about T+9 months, so 2025 is expected shortly). No observation flags in the data.
- ⚠️ **Netherlands excluded by Eurostat:** Statistics Netherlands uses a different,
  register-based method, so Eurostat does not publish the indicator for NL. Known gap.
- ⚠️ **Possible unflagged breaks:** the metadata warns that LFS definition changes can cause
  breaks in the FTE ratio, with "an additional break between 2020 and 2021" for some countries.
  None are flagged in the data.
- **Why primary:** a consistent national-accounts series with no compiler change. It replaces
  `earn_nt_net` for wage growth and real wage growth after that dataset's 2024 break.

### Net earnings – `earn_nt_net` (secondary, used up to 2023)

- **Title:** Annual net earnings
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/earn_nt_net/default/table?lang=en
- **Frequency / unit:** annual / EUR
- **Filters:**
  - `currency=EUR`: one common currency for comparing countries (PPS also exists; EUR is what people are paid in).
  - `estruct=NET`: net earnings (after tax and social contributions), as in the plan.
  - `ecase=P1_NCH_AW100`: single person without children earning 100% of the average wage, as in the plan.
- **Coverage:** all 28 geos, 2010–2025 in raw; Croatia and EU27_2020 from 2013, Cyprus from 2014.
- ⚠️ **Break in series from 2024, not repaired:**
  - **Source change:** compiled by the OECD (Taxing Wages model) until 2023 and by the
    Commission's JRC (EUROMOD) from 2024 ([metadata](https://ec.europa.eu/eurostat/cache/metadata/en/earn_net_esms.htm)).
    2024 is flagged `b`.
  - **2024 is on a monthly scale:** every 2024 value is about 1/12 of the 2023 value
    (HR 12,601 → 1,267; EU27 28,324 → 2,398).
  - **2025 is on a new basis:** back at an annual level, but the 2023 → 2025 change ranges from
    −10% (NL) to +46% (BG), so 2025 is not comparable with 2023 (HR 16,892, +34%).
  - `earn_nt_netft` has the same break, so it is not an alternative.
- **Decision:** `earn_nt_net` is used **only for 2010–2023**, as a secondary "net take-home pay"
  indicator (net of tax and contributions for a typical single worker). Raw keeps all years
  unchanged; the cut-off is applied in the transform (Phase 3) and recorded in the model as
  `warehouse.dim_indicator.valid_to_year = 2023`. Wage growth after 2023 uses `nama_10_fte`.

### Inflation (HICP) – `prc_hicp_minr`

- **Title:** Harmonised index of consumer prices (HICP) - ECOICOP ver.2 - indices and rates of change, monthly data
- **URL:** https://ec.europa.eu/eurostat/databrowser/view/prc_hicp_minr/default/table?lang=en
- **Frequency / unit:** monthly / index (2025 = 100) and annual rate of change (%)
- **Why not `prc_hicp_manr` (the plan's choice):** it is discontinued. Its title is now "HICP -
  monthly data (annual rate of change) (1997-2025)" and its last update was 2026-02-06, with
  data ending 2025-12. Eurostat moved HICP to the ECOICOP ver.2 classification in 2026 and
  publishes it in `prc_hicp_minr`, which contains back-cast history (HR from 1998, EU27 from
  2000) and is updated monthly. Over 2010–2025 the two datasets agree: for HR 180 of 192
  months are identical and the rest differ by at most ±0.1 pp (EU27: 184 of 192).
- **Filters:**
  - `unit=RCH_A,I25`: both units are extracted and split into **two indicators**:
    - **`HICP_INDEX`** (`unit=I25`, index 2025 = 100): basis for **annual inflation**,
      computed in Phase 4 as annual average index / previous year's annual average index − 1.
      This is how Eurostat computes its annual average rate: over 2011–2025 the index-derived
      rate, rounded to 0.1, equals the official rate in the annual dataset `prc_hicp_ainr`
      (`unit=RCH_A_AVG`) for **all 420** country-years checked (EU27 + EU27_2020).
    - **`HICP_ANNUAL_RATE`** (`unit=RCH_A`): the headline monthly figure (change on the same
      month of the previous year), for monthly charts.
    - Why `I25` and not `I15` (2015 = 100, also in the dataset): 2025 = 100 is the base of
      Eurostat's ECOICOP ver.2 HICP (the annual index in `prc_hicp_ainr` is 2025 = 100 too),
      `I25` includes the latest flash estimate (one month more), and the rounded `I15` values
      gave 9 of 420 annual rates that differ from the official ones by 0.1 pp. The base year
      does not affect growth rates.
    - Why not `prc_hicp_ainr` directly: it is annual only. The monthly index allows both
      annual inflation and monthly/partial-year views from a single source; `prc_hicp_ainr`
      remains a reference for spot checks.
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

`warehouse.dim_flag` holds Eurostat's full official `OBS_FLAG` codelist (42 codes, mostly
combinations such as `bp` = break + provisional) plus `''` for "no flag". Source:
https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/codelist/ESTAT/OBS_FLAG.
Confidentiality is a separate attribute (`CONF_STATUS`), not a flag.

**Combined flags.** Eurostat sends several flags on one observation as one code with the
letters concatenated in alphabetical order (e.g. `be`, `bp`, `bep` in `demo_pjan`), and the
official codelist (so `dim_flag`) contains these combinations. No combined flags currently
occur in our six datasets. The transform maps a raw flag via `warehouse.normalize_flag()`:
NULL becomes `''` (no flag); separators (comma, space, semicolon) are removed and the letters
are lower-cased, de-duplicated and sorted, so `b,p`, `pb` and `bp` all map to `bp`. A flag
that still has no match in `dim_flag` fails the transform (it is never dropped silently).

Single flags seen in the loaded data:

| Flag | Meaning |
|---|---|
| `b` | break in time series |
| `d` | definition differs (see metadata) |
| `e` | estimated |
| `p` | provisional |

## Reference data for dimensions

Seeded from `seeds/*.csv` into the `warehouse` schema (Phase 2).

- **Euro adoption years** (`dim_country.euro_adoption_year`): from the ECB's list of euro area
  members, https://www.ecb.europa.eu/euro/intro/html/map.en.html (checked 2026-10-09). The year
  is the year of joining (e.g. 1999 for the founding members, cash from 2002; Greece 2001,
  Croatia 2023, Bulgaria 2026). NULL for CZ, DK, HU, PL, RO, SE.
- **Regions** (`dim_country.region`): UN M49 geoscheme sub-regions,
  https://unstats.un.org/unsd/methodology/m49/. It is an official, neutral and widely used
  classification, rather than an ad-hoc "Central-Eastern" grouping. Northern: DK, EE, FI, IE,
  LT, LV, SE; Western: AT, BE, DE, FR, LU, NL; Southern: EL, ES, HR, IT, MT, PT, SI (+ CY);
  Eastern: BG, CZ, HU, PL, RO, SK.
  **Deviation:** M49 places Cyprus in Western Asia. Since this dashboard only has European
  regions, Cyprus is mapped to **Southern Europe** (as in EuroVoc).
- **ISO codes** (`dim_country.iso_alpha2`): ISO 3166-1 alpha-2, for Power BI maps. Equal to
  the Eurostat geo code except Greece (Eurostat `EL`, ISO `GR`).
- **Flags** (`dim_flag`): see [Observation flags](#observation-flags).

## Licence and attribution

Eurostat data is licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
([Eurostat copyright notice](https://ec.europa.eu/eurostat/about-us/policies/copyright)).

Attribution text:

> Source: Eurostat (nama_10_fte, earn_nt_net, prc_hicp_minr, prc_hpi_q, une_rt_m, nama_10_pc), © European Union, CC BY 4.0. Data retrieved via the Eurostat dissemination API.
