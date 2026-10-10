# Power BI guide

How to build the report in Power BI Desktop on top of the `analytics` schema. Everything here is
prepared in the database and this repo. The finished report is `powerbi/eu_dashboard.pbip` (Power
BI project: model in TMDL, report in PBIR, both plain text and diffable) with a `.pbix` copy and a
PDF export next to it; this guide documents how it is built. Before starting, run `make up` and
`make pipeline` so the views are filled.

Contents: [1. Connect](#1-connect) · [2. Import](#2-what-to-import) ·
[3. Model](#3-model-relationships-and-settings) · [4. Theme](#4-theme) ·
[5. Measures](#5-dax-measures) · [6. Pages](#6-pages) · [7. Check the numbers](#7-check-the-numbers) ·
[8. Export](#8-export)

---

## 1. Connect

1. **Home → Get data → PostgreSQL database**.
2. Settings (from `.env`):

   | Field | Value |
   |---|---|
   | Server | `127.0.0.1:5432`, i.e. `127.0.0.1:<POSTGRES_PORT>`. Use `127.0.0.1`, not `localhost`, which stalls on Windows via IPv6. |
   | Database | `eu_dashboard` (`POSTGRES_DB`) |
   | Data Connectivity mode | **Import**. The data is small (~25,000 rows), so Import keeps the report fast and lets the `.pbix` work without the database. |

3. Credentials: choose the **Database** tab (not Windows):
   - User name: `powerbi_reader`
   - Password: the value of `POWERBI_READER_PASSWORD` in `.env`

   This role can only `SELECT` from the `analytics` views. It has no access to the `raw`,
   `warehouse` or `quality` schemas, and its sessions are read-only.
4. **Encryption / SSL.** The local Docker Postgres has no SSL, so Power BI may report that it
   was "unable to connect to the data source using an encrypted connection":
   - In the prompt that follows, click **OK** to connect without encryption. This is fine for
     a database on your own machine (127.0.0.1); the traffic never leaves the computer.
   - If there is no prompt and the connection keeps failing: **File → Options and settings →
     Data source settings** → select `127.0.0.1:5432;eu_dashboard` → **Edit Permissions** →
     untick **Encrypt connections** → OK, then refresh.
   - Do not do this for a database on another machine or in the cloud. Enable SSL on that
     server instead.

## 2. What to import

In the Navigator, expand `eu_dashboard → analytics` and tick only these **8 views**:

| View | Rows | Role in the model |
|---|---|---|
| `bi_dim_country` | 28 | dimension: countries, Croatia and EU first |
| `bi_dim_year` | 17 | dimension: years 2010–2026 |
| `bi_dim_indicator` | 11 | dimension: indicators incl. the derived ones |
| `v_annual_summary` | ~3,400 | **main fact**: every indicator per country and complete year |
| `v_observations` | ~20,000 | fact: monthly and quarterly detail (inflation, unemployment, house prices) |
| `v_country_rank` | ~2,800 | fact: ranks per indicator and year (ranking rules live in SQL) |
| `v_quality_latest` | 54 | data quality page: results of the latest quality run |
| `v_known_gaps` | 7 | data quality page: documented missing data |

**Skip these** (they stay in the database for SQL users and as a cross-check, but the measures
in section 5 compute the same numbers from `v_annual_summary`, so importing them would only
duplicate data):

| View | Replaced by measure |
|---|---|
| `v_yoy_change` | `YoY %`, `YoY Change` |
| `v_index_base_2015` | `Change Since Base Year %`, `Index Base Year` |
| `v_real_wage_growth` | `Real Wage Growth %`, `Real Wage Index 2010` |
| `v_housing_affordability` | `Housing Affordability Ratio` |
| `v_gdp_relative_to_eu` | `Croatia vs EU Index` |

Click **Load** (not Transform). No Power Query steps are needed.

## 3. Model: relationships and settings

### Relationships

Open **Model view** and delete any relationships Power BI auto-detected. Then create exactly
these (Manage relationships → New). All of them are **one-to-many (1:\*)**, the dimension on the
"one" side, **cross filter direction: Single**, **active**:

| # | From (one side) | To (many side) | Column |
|---|---|---|---|
| 1 | `bi_dim_country` | `v_annual_summary` | `country_code` |
| 2 | `bi_dim_country` | `v_observations` | `country_code` |
| 3 | `bi_dim_country` | `v_country_rank` | `country_code` |
| 4 | `bi_dim_country` | `v_known_gaps` | `country_code` |
| 5 | `bi_dim_year` | `v_annual_summary` | `year` |
| 6 | `bi_dim_year` | `v_observations` | `year` |
| 7 | `bi_dim_year` | `v_country_rank` | `year` |
| 8 | `bi_dim_indicator` | `v_annual_summary` | `indicator_code` |
| 9 | `bi_dim_indicator` | `v_observations` | `indicator_code` |
| 10 | `bi_dim_indicator` | `v_country_rank` | `indicator_code` |
| 11 | `bi_dim_indicator` | `v_known_gaps` | `indicator_code` |

`v_quality_latest` stays **unrelated**. Its `subject` mixes indicator and dataset codes, and the
page only uses its own columns.

All dimension keys are unique, and every key in the fact views exists in its dimension (checked
in the database: 0 orphans), so Power BI accepts these as 1:\* without a blank member.

### Model settings

1. **File → Options → Current file → Data load**: untick **Auto date/time**. `bi_dim_year` is
   the year dimension; monthly charts use `v_observations[period_date]` directly.
2. **Sort columns** (Table view → select column → *Sort by column*):
   - `bi_dim_country[country_name]` and `bi_dim_country[country_short_name]` by
     `bi_dim_country[sort_order]`, so Croatia and the EU come first everywhere.
   - `bi_dim_indicator[indicator_name]` by `bi_dim_indicator[sort_order]`.
3. **Hide** the key columns on the fact side (`country_code`, `year`, `indicator_code` in
   `v_annual_summary`, `v_observations`, `v_country_rank`, `v_known_gaps`), so slicers and
   visuals always use the dimension columns.
4. **Data category**: set `bi_dim_country[country_name]` to *Country/Region* (for the map).
5. **Summarization**: set `bi_dim_year[year]` and all `year` / `sort_order` columns to
   *Don't summarize*.
6. **Base year table** (for `Change Since Base Year %`): Modeling → **New table**:

   ```DAX
   Base Year =
   SELECTCOLUMNS ( FILTER ( bi_dim_year, bi_dim_year[has_annual_data] ), "Base Year", bi_dim_year[year] )
   ```

   Leave it **unrelated**. It only feeds a slicer (default 2010).
7. Create a table **`_Measures`** (Enter data → one empty column → name `_Measures`) to hold all
   measures from section 5, then hide its column.

## 4. Theme

**View → Themes → Browse for themes** → `powerbi/theme.json`.

- **Croatia** is always `#C8102E` (red) and **EU27** always `#1F4E9E` (blue). A theme cannot
  bind a colour to a category *value*, so every visual with a country legend sets these two
  colours explicitly (**Format → Lines/Columns → Colors**, per series).
- The theme's data colours (`dataColors`) are 16 muted colours **without red or blue** (teal,
  amber, mauve, green, brown, slate, ...). Power BI hands out palette colours only to series
  without an explicit colour, so with red and blue in the palette another country (e.g.
  Austria) would get Croatia's red. Keeping them out of the palette makes Croatia and the EU the
  only red and blue series.
- In bar/column charts of all countries use **Format → Columns/Bars → Colors → fx → Format
  style: Field value → `bi_dim_country[highlight_colour]` (First)**: Croatia red, EU blue,
  other countries grey. The ranking table uses the same column for the font colour of the name.
- Fonts: Segoe UI (labels) and Segoe UI Semibold (titles, KPI numbers). Pages have a light grey
  background and white cards.

## 5. DAX measures

Create each measure in `_Measures` (Modeling → New measure) and set the **format** shown.
Where a measure needs another measure's value as a filter, it stores it in a `VAR` first. That
keeps the `CALCULATE` filter a simple column comparison, which works in every Power BI version. All
measures are built on `v_annual_summary` (complete years only). They return **blank** rather
than a misleading number when the context is ambiguous (e.g. several countries at once).

### Building blocks

```DAX
-- The value for exactly one country, indicator and year; blank otherwise (never sums countries).
Annual Value =
IF ( COUNTROWS ( v_annual_summary ) = 1, SUM ( v_annual_summary[value] ) )
```
Format: Decimal number, 1 decimal place. The base for every other measure.

```DAX
-- The same for monthly/quarterly detail charts (axis: v_observations[period_date]).
Period Value =
IF ( COUNTROWS ( v_observations ) = 1, SUM ( v_observations[value] ) )
```
Format: 1 decimal place. Gives the monthly HICP rate, unemployment and quarterly house prices.

```DAX
Wage NAC =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "WAGE_NAC" )

HICP Index =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "HICP_INDEX" )

HICP Inflation =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "HICP_INFLATION" )

House Price Index =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "HOUSE_PRICE_INDEX" )
```
Fixed-indicator helpers (gross wage in national currency, annual average HICP index, annual
inflation in %, annual average house price index), so the measures below work whatever indicator
is selected.

```DAX
Latest Wage Year =
CALCULATE (
    MAX ( v_annual_summary[year] ),
    REMOVEFILTERS ( bi_dim_year ),
    REMOVEFILTERS ( bi_dim_indicator ),
    bi_dim_indicator[indicator_code] = "WAGE_NAC"
)
```
Format: Whole number, no thousands separator. The latest year with wage data (2024 now), used by
the "(latest)" KPI measures.

### Requested measures

**1. Latest value**

```DAX
Latest Value =
VAR LatestYear =
    CALCULATE ( MAX ( v_annual_summary[year] ), REMOVEFILTERS ( bi_dim_year ) )
RETURN
    CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = LatestYear )

Latest Year =
CALCULATE ( MAX ( v_annual_summary[year] ), REMOVEFILTERS ( bi_dim_year ) )
```
The value in the most recent complete year for the selected country and indicator, ignoring the
year filter. `Latest Year` labels it (format: whole number, no separator). Format `Latest Value`
like `Annual Value`.

**2. YoY %**

```DAX
YoY % =
VAR ThisYear = SELECTEDVALUE ( bi_dim_year[year] )
VAR Curr = [Annual Value]
VAR Prev =
    CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = ThisYear - 1 )
VAR IsRate = SELECTEDVALUE ( bi_dim_indicator[is_rate], FALSE () )
RETURN
    IF ( NOT IsRate && NOT ISBLANK ( Curr ) && NOT ISBLANK ( Prev ), DIVIDE ( Curr, Prev ) - 1 )

YoY Change =
VAR ThisYear = SELECTEDVALUE ( bi_dim_year[year] )
VAR Curr = [Annual Value]
VAR Prev =
    CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = ThisYear - 1 )
RETURN
    IF ( NOT ISBLANK ( Curr ) && NOT ISBLANK ( Prev ), Curr - Prev )
```
`YoY %` (format: Percentage, 1 decimal) is the change on the previous year; it is blank for rates
(unemployment, inflation), because a % change of a % is misleading. Use `YoY Change` (format: 1
decimal) for those: the change in percentage points.

**3. Change since base year**

```DAX
Change Since Base Year % =
VAR BaseYear = SELECTEDVALUE ( 'Base Year'[Base Year], 2010 )
VAR ThisYear =
    IF (
        HASONEVALUE ( bi_dim_year[year] ),
        VALUES ( bi_dim_year[year] ),
        CALCULATE ( MAX ( v_annual_summary[year] ), REMOVEFILTERS ( bi_dim_year ) )
    )
VAR Curr =
    CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = ThisYear )
VAR Base =
    CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = BaseYear )
VAR IsRate = SELECTEDVALUE ( bi_dim_indicator[is_rate], FALSE () )
RETURN
    IF ( NOT IsRate && NOT ISBLANK ( Curr ) && NOT ISBLANK ( Base ), DIVIDE ( Curr, Base ) - 1 )

Index Base Year =
VAR Change = [Change Since Base Year %]
RETURN IF ( NOT ISBLANK ( Change ), ( 1 + Change ) * 100 )
```
The change from the base year (slicer `'Base Year'`, default 2010) to the year in context, or to
the latest year on a card without a year. Format: Percentage, 1 decimal. `Index Base Year`
(format: 1 decimal) shows the same as an index line, e.g. house prices vs wages with base 2015.

**4. Real wage growth**

```DAX
Real Wage Growth % =
VAR ThisYear = SELECTEDVALUE ( bi_dim_year[year] )
VAR Wage = [Wage NAC]
VAR WagePrev =
    CALCULATE ( [Wage NAC], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = ThisYear - 1 )
VAR Inflation = [HICP Inflation] -- in %, e.g. 4.02
RETURN
    IF (
        NOT ISBLANK ( Wage ) && NOT ISBLANK ( WagePrev ) && NOT ISBLANK ( Inflation ),
        DIVIDE ( Wage, WagePrev ) / ( 1 + Inflation / 100 ) - 1
    )
```
`(1 + nominal wage growth) / (1 + inflation) − 1`, not a simple difference, with wages in national
currency (no exchange-rate effects). Format: Percentage, 1 decimal.

**5. Cumulative real wage index**

```DAX
Real Wage Index 2010 =
VAR Wage = [Wage NAC]
VAR Wage2010 =
    CALCULATE ( [Wage NAC], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = 2010 )
VAR Prices = [HICP Index]
VAR Prices2010 =
    CALCULATE ( [HICP Index], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = 2010 )
RETURN
    IF (
        NOT ISBLANK ( Wage ) && NOT ISBLANK ( Wage2010 )
            && NOT ISBLANK ( Prices ) && NOT ISBLANK ( Prices2010 ),
        DIVIDE ( Wage, Wage2010 ) / DIVIDE ( Prices, Prices2010 ) * 100
    )

Real Wage Index (latest) =
VAR LatestYear = [Latest Wage Year]
RETURN
    CALCULATE ( [Real Wage Index 2010], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = LatestYear )
```
Real wages with 2010 = 100: 116.6 means "16.6 % higher in real terms than in 2010". Format: 1
decimal. The year-by-year chain of real growth rates telescopes to (wage / wage 2010) / (prices /
prices 2010), so this equals `v_real_wage_growth.real_wage_index_2010` (checked: identical for all
405 country-years). The only difference: across a gap in the wage series the view gives blank,
and this measure still compares with 2010. The current data has no such gaps.
`(latest)` is for KPI cards without a year.

**6. Housing affordability ratio**

```DAX
Housing Affordability Ratio =
VAR Houses = [House Price Index]
VAR Houses2015 =
    CALCULATE ( [House Price Index], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = 2015 )
VAR Wage = [Wage NAC]
VAR Wage2015 =
    CALCULATE ( [Wage NAC], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = 2015 )
RETURN
    IF (
        NOT ISBLANK ( Houses ) && NOT ISBLANK ( Houses2015 )
            && NOT ISBLANK ( Wage ) && NOT ISBLANK ( Wage2015 ),
        DIVIDE ( Houses, Houses2015 ) / DIVIDE ( Wage, Wage2015 ) * 100
    )

Housing Affordability Ratio (latest) =
VAR LatestYear = [Latest Wage Year]
RETURN
    CALCULATE ( [Housing Affordability Ratio], REMOVEFILTERS ( bi_dim_year ), bi_dim_year[year] = LatestYear )
```
House prices relative to wages, both 2015 = 100 and in national currency. Above 100, housing is
less affordable than in 2015. Format: 1 decimal. Equals `v_housing_affordability` (checked).

**7. Croatia vs EU gap**

```DAX
Croatia Value =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_country ), bi_dim_country[country_code] = "HR" )

EU Value =
CALCULATE ( [Annual Value], REMOVEFILTERS ( bi_dim_country ), bi_dim_country[country_code] = "EU27_2020" )

Croatia vs EU Index =
DIVIDE ( [Croatia Value], [EU Value] ) * 100

Croatia - EU Gap =
VAR Hr = [Croatia Value]
VAR Eu = [EU Value]
RETURN IF ( NOT ISBLANK ( Hr ) && NOT ISBLANK ( Eu ), Hr - Eu )

Index vs EU =
DIVIDE ( [Annual Value], [EU Value] ) * 100
```
For the selected indicator and year: Croatia as % of the EU level (format: 1 decimal; GDP per
capita 77.6 = 77.6 % of the EU), and the absolute gap in the indicator's unit (format: 1 decimal;
percentage points for rates). Use `EU = 100` for levels (GDP, wages in EUR) and the gap for rates. `Index vs EU` is
the same ratio for whichever country is in context, for bar charts of all countries.

### Small helpers for the data quality page

```DAX
Checks Passed = CALCULATE ( COUNTROWS ( v_quality_latest ), v_quality_latest[status] = "pass" )
Checks Failed = CALCULATE ( COUNTROWS ( v_quality_latest ), v_quality_latest[status] = "fail" )
Checks Warned = CALCULATE ( COUNTROWS ( v_quality_latest ), v_quality_latest[status] = "warn" )
Quality Run Status = SELECTEDVALUE ( v_quality_latest[run_status], "no run" )
Quality Run Time = MAX ( v_quality_latest[run_finished_at] )
```
Counts of results by status, plus the run status and finish time for cards (format the time as
`yyyy-mm-dd hh:mm`).

### Display helpers (text and fixed-indicator measures)

Card and table values that must look the same on every machine are **text measures** with an
explicit `en-US` locale. A number format on the visual follows the Desktop/viewer locale (e.g.
`32370,2` on a Croatian system) and was not applied reliably to the new card visual.

```DAX
Latest Wage Year Text =
VAR LatestYear = [Latest Wage Year]
RETURN IF ( NOT ISBLANK ( LatestYear ), FORMAT ( LatestYear, "0" ) )

Latest Year Text =            -- latest year of the indicator in context, " (p)" if provisional
Latest GDP Year Text = CALCULATE ( [Latest Year Text], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "GDP_PC_PPS" )

Country KPI Subtitle = "Wages and house prices: " & [Latest Wage Year Text] & " · GDP: " & [Latest GDP Year Text]
GDP vs EU Subtitle =          -- "Croatia, 2025 (p) · EU27 = 100"
Unemployment vs EU Subtitle = -- "Croatia minus EU27, 2025"

GDP per Capita Text =
VAR Gdp =
    CALCULATE ( [Latest Value], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "GDP_PC_PPS" )
RETURN IF ( NOT ISBLANK ( Gdp ), FORMAT ( Gdp, "#,0", "en-US" ) )

Croatia - EU Gap Text =
VAR Gap = [Croatia - EU Gap]
VAR Sign = SWITCH ( TRUE (), Gap < 0, UNICHAR ( 8722 ), Gap > 0, "+", "" )
RETURN IF ( NOT ISBLANK ( Gap ), Sign & FORMAT ( ABS ( Gap ), "0.0", "en-US" ) & " pp" )

Rank Value Text =
VAR RankValue = SELECTEDVALUE ( v_country_rank[value] )
VAR Code = SELECTEDVALUE ( v_country_rank[indicator_code] )
VAR Pattern = IF ( Code IN { "WAGE_EUR", "NET_EARNINGS", "GDP_PC_PPS" }, "#,0", "0.0" )
RETURN IF ( NOT ISBLANK ( RankValue ), FORMAT ( RankValue, Pattern, "en-US" ) )

House Price Index (Base Year) = CALCULATE ( [Index Base Year], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "HOUSE_PRICE_INDEX" )
Wage Index (Base Year) = CALCULATE ( [Index Base Year], REMOVEFILTERS ( bi_dim_indicator ), bi_dim_indicator[indicator_code] = "WAGE_NAC" )
```
The full definitions of the shortened ones are in
`powerbi/eu_dashboard.SemanticModel/definition/tables/_Measures.tmdl`. The last two give the
Housing chart a legend that reads "House prices" / "Wages" (display names) instead of the
indicator names. `v_country_rank[has_provisional]` has the format string `"p";"p";`, so the
ranking table shows "p" or nothing.

## 6. Pages

Canvas 16:9 (1280 × 720). Each page has a title text box (top left), a one-sentence takeaway
under it, and the source line at the bottom: *Source: Eurostat (nama_10_fte, earn_nt_net,
prc_hicp_minr, prc_hpi_q, une_rt_m, nama_10_pc), © European Union, CC BY 4.0.*

**Synced slicers** (View → Sync slicers):
- **Country**: `bi_dim_country[country_short_name]`, multi-select, default Croatia + EU27.
  Synced on *Croatia vs EU* and *Housing* (visible on both).
- **Year range**: `bi_dim_year[year]` as a *Between* slider, default 2010–2025. Synced on
  *Croatia vs EU*, *Country comparison* and *Housing*.

### Page 1 – Overview

**Key finding:** everyday life became *more* affordable, housing *less*. Croatian real wages are
16.6 % above 2010 (EU: 4.5 %), but house prices rose about 20 % more than wages since 2015
(findings 1 and 3).

| Visual | Fields / measures | Notes |
|---|---|---|
| 2 KPI cards (new card visual, 3 tiles each): Croatia (top), EU27 (bottom) | `Real Wage Index (latest)`, `Housing Affordability Ratio (latest)`, `GDP per Capita Text` | each card: visual-level filter `bi_dim_country[country_code]` = HR or EU27_2020. Tile labels: "Real wages vs 2010 (2010 = 100)", "House prices vs wages (2015 = 100)", "GDP per capita, PPS". Subtitle: `Country KPI Subtitle` (fx) |
| 2 KPI cards | `Croatia vs EU Index` (indicator filter `GDP_PC_PPS`, year filter = latest annual year via `bi_dim_year[is_latest_annual_year]` = True); `Croatia - EU Gap Text` (indicator `UNEMPLOYMENT_RATE`, same year filter) | titles "GDP per capita vs EU" (77.6) and "Unemployment vs EU" (−1.1 pp); subtitles `GDP vs EU Subtitle`, `Unemployment vs EU Subtitle` |
| Line chart | X: `bi_dim_year[year]`; Y: `Real Wage Index 2010`; Legend: `bi_dim_country[country_short_name]` | visual filter: country in (HR, EU27_2020); constant line at 100 |
| Text box | 3–4 findings from `docs/findings.md` (1, 2, 3, 4), one sentence each | mark provisional numbers (2025 GDP) with "(p)" |

No slicers on this page: it always shows Croatia vs EU at the latest data.

### Page 2 – Croatia vs EU

**Key finding:** Croatia had higher inflation than the EU (10.7 % and 8.4 % in 2022–2023), but
wages outpaced it, so real wages kept rising while EU real wages fell (finding 2).
Unemployment fell from 17.4 % (2013) to 4.9 %, below the EU (finding 5).

| Visual | Fields / measures | Notes |
|---|---|---|
| 6 line charts in a 3 × 2 grid, one per indicator | X: `bi_dim_year[year]`; Y: `Annual Value`; Legend: `bi_dim_country[country_short_name]` | one visual filter each: WAGE_NAC, HICP_INFLATION, UNEMPLOYMENT_RATE, HOUSE_PRICE_INDEX, GDP_PC_PPS, NET_EARNINGS; title with the unit. Separate charts instead of one small-multiples chart, so each has its own title, unit and Y axis |
| Clustered column chart | X: `bi_dim_year[year]`; Y: `Real Wage Growth %`; Legend: country | years 2011+; data labels off (they overlap), values in the tooltip; this shows 2022–2023 |
| Line chart (monthly) | X: `v_observations[period_date]` (continuous); Y: `Period Value`; Legend: country | visual filter: indicator = `HICP_ANNUAL_RATE`; title "Inflation, % on same month last year" |
| Slicers | Country (synced), Year range (synced) | |

Tooltip tip: add `bi_dim_indicator[unit]` and `YoY %` / `YoY Change` to the six line charts'
tooltips.

### Page 3 – Country comparison

**Key finding:** Croatia is catching up: GDP per capita rose from 61 % to 78 % of the EU average
(2010 → 2025 p). Croatia ranks 12th of 26 on real wage gains since 2010 (finding 4, finding 1).

| Visual | Fields / measures | Notes |
|---|---|---|
| Filled map | Location: `bi_dim_country[country_name]` (data category Country/Region); Color saturation: `Annual Value` | visual filter `bi_dim_country[is_aggregate]` = False; needs one indicator and one year (slicers below). Enable map visuals under File → Options → Security if prompted |
| Table (ranking) | `bi_dim_country[country_short_name]`, `Rank Value Text`, `v_country_rank[country_rank]`, `v_country_rank[countries_ranked]`, `v_country_rank[has_provisional]` | sort by rank; font colour fx → field value `bi_dim_country[highlight_colour]` on the name column; values right-aligned (no decimals for wages, earnings and GDP, 1 decimal otherwise) |
| Bar chart | Y: `bi_dim_country[country_short_name]`; X: `Index vs EU` | visual filter: indicator = `GDP_PC_PPS` (fixed, independent of the indicator slicer: Edit interactions → none); bars coloured by `highlight_colour` (fx); constant line at 100; sort descending. Title "GDP per capita in PPS, EU = 100" |
| Slicers | Indicator: `bi_dim_indicator[indicator_name]`, single select, filtered to the ranked indicators (WAGE_EUR, NET_EARNINGS, GDP_PC_PPS, UNEMPLOYMENT_RATE, HICP_INFLATION, REAL_WAGE_GROWTH, HOUSING_AFFORDABILITY); Year: single-value dropdown (default latest) | the year slicer here is a *single* year, not synced with the range slider |

Caption under the table: "Rank 1 = best. Higher is better for wages, earnings, GDP and real
wage growth; lower for unemployment and house prices relative to wages; inflation ranks by
distance from 2 % (ECB target)." `v_country_rank[ranking_rule]` holds the same rule for a tooltip.

Note: the map and bar chart use `Annual Value`, which only covers warehouse indicators and
`HICP_INFLATION`. For `REAL_WAGE_GROWTH` and `HOUSING_AFFORDABILITY` use the ranking table.

### Page 4 – Housing

**Key finding:** between 2015 and 2024 Croatian house prices doubled (+99 %) while wages rose
67 %, so housing became about 20 % less affordable (EU: 15 %), and prices rose another 14 % in
2025. Real wages can rise while housing gets less affordable because the HICP excludes
owner-occupied housing and house purchases (finding 3 and the HICP section of the findings).

| Visual | Fields / measures | Notes |
|---|---|---|
| Line chart | X: `bi_dim_year[year]`; Y: `House Price Index (Base Year)` (display name "House prices") and `Wage Index (Base Year)` ("Wages") | visual filter: country = HR; set the `Base Year` slicer to 2015 for this page (or a page filter `'Base Year'[Base Year]` = 2015). Title "Croatia: house prices vs wages, 2015 = 100" |
| Line chart | X: `bi_dim_year[year]`; Y: `Housing Affordability Ratio`; Legend: country | constant line at 100 labelled "2015 level"; years 2015+ |
| Bar chart | Y: `bi_dim_country[country_short_name]`; X: `Housing Affordability Ratio` | year filter 2024 (latest with wages); bars coloured by `highlight_colour`; sort descending (Portugal 149.5 top) |
| Line chart (quarterly) | X: `v_observations[period_date]`; Y: `Period Value`; Legend: country | indicator = `HOUSE_PRICE_INDEX`; shows 2025–2026 after wage data ends |
| Text box | "Why can real wages rise while housing gets less affordable?" + 2 sentences from `docs/findings.md` (HICP excludes owner-occupied housing; Eurostat 2023) | |
| Slicers | Country (synced), Year range (synced) | Greece has no house price index, the Netherlands no wage data |

### Page 5 – Data quality

**Key finding:** the data behind the report passed all checks of the latest run (54 of 54).
The 7 known gaps are documented exceptions where Eurostat publishes no data (Greece house
prices, Netherlands wages, net earnings start years).

| Visual | Fields / measures | Notes |
|---|---|---|
| 4 cards | `Quality Run Status`, `Quality Run Time`, `Checks Passed`, `Checks Failed` + `Checks Warned` | colour the status card: passed green, failed red (fx rules) |
| Matrix | Rows: `v_quality_latest[check_description]`; Columns: `v_quality_latest[status]`; Values: count of `subject` | shows 7 checks × pass/fail/warn |
| Table | `check_name`, `severity`, `subject`, `status`, `issue_count`, `message` from `v_quality_latest` | filter `status` ≠ pass by default (shows "no issues" when empty), or show all sorted by status |
| Table | `bi_dim_country[country_short_name]`, `bi_dim_indicator[indicator_name]`, `v_known_gaps[gap_description]`, `v_known_gaps[reason]` | |
| Text box | what errors and warnings mean (error fails the pipeline, warning only reports), and that CI runs these checks weekly against the live Eurostat API | |

No slicers.

## 7. Check the numbers

After building the measures, put them in a table with `bi_dim_country[country_short_name]` and
`bi_dim_year[year]` and compare with these values (from the SQL views, 2026-10-09 data):

| Measure | Country | Year | Expected |
|---|---|---|---|
| `Latest Value` (GDP_PC_PPS) | Croatia | – (2025) | 32,370.2 |
| `YoY %` (WAGE_NAC) | Croatia | 2024 | 8.2 % (8.24) |
| `Change Since Base Year %` (HOUSE_PRICE_INDEX, base 2015) | Croatia | 2024 | 99.4 % |
| `Change Since Base Year %` (WAGE_NAC, base 2010) | Croatia | 2024 | 66.3 % |
| `Real Wage Growth %` | Croatia | 2022 / 2023 / 2024 | 1.6 % / 4.6 % / 4.1 % (1.61, 4.58, 4.06) |
| `Real Wage Index 2010` | Croatia / EU27 | 2024 | 116.6 / 104.5 |
| `Housing Affordability Ratio` | Croatia / EU27 | 2024 | 119.5 / 115.2 |
| `Croatia vs EU Index` (GDP_PC_PPS) | – | 2025 | 77.6 |
| `Croatia - EU Gap` (UNEMPLOYMENT_RATE) | – | 2025 | −1.1 pp |

A different number usually means a relationship is missing or bidirectional, `Auto date/time`
is still on, or a visual filter on the indicator is missing.

## 8. Export

- Save as `powerbi/eu_dashboard.pbix` (committed; `.gitignore` allows `powerbi/*.pbix`).
- **File → Export → Export to PDF** → `powerbi/eu_dashboard.pdf`.
- Screenshots for the README: `make screenshots` renders each PDF page to
  `docs/images/powerbi_<page>.png` (PyMuPDF and Pillow via `uv run --with`, not project
  dependencies).
- "Publish to web" needs a work or school Microsoft account. Without one, the PDF and
  screenshots are enough.
- To refresh with new data: `make pipeline`, then **Home → Refresh** in Power BI Desktop.
