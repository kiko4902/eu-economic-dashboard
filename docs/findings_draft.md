# Findings (draft)

**Question:** has life in Croatia (and the EU) become more or less affordable since 2010?

**Short answer:** for everyday consumption, **more affordable**. Croatian wages have grown
faster than consumer prices, by more than the EU average, and the gap widened after the
2022–2023 inflation shock. For **housing, less affordable**: since 2015, house prices in
Croatia have risen much faster than wages, more so than in the EU as a whole.

Data: Eurostat, retrieved 2026-10-09 (see `docs/data_sources.md`). All numbers come from the
`analytics` views; each finding lists its query. Annual figures use complete years only, so
2026 is not included. Comparison countries: Slovenia (neighbour, euro area), Poland (fast
converger, own currency) and Italy (slow growth); others where notable.

**Flagged data (checked against the views' flag columns):**
- **Provisional (`p`):**
  - 2025 GDP per capita for Croatia, Italy and 12 other geos (14 of 28; the EU aggregate's 2025
    value is not provisional), so the 2025 figures in finding 4 may be revised.
  - Hungary's 2024 house prices (finding 3).
- **Break (`b`):** Poland's and Italy's 2010 GDP per capita (finding 4).
- All other figures quoted below have no provisional, estimated or break flags.
- Wage data (`nama_10_fte`) can have unflagged LFS breaks around 2020–2021.

---

## 1. Real wages in Croatia are 16.6 % higher than in 2010; the EU average is up 4.5 %

The real wage index (gross average full-time adjusted salary in national currency, deflated by
HICP, 2010 = 100) was **116.6 for Croatia in 2024** and **104.5 for EU27_2020**. Croatia ranks
12th of 26 member states (no data for the Netherlands). Within the comparison group: Bulgaria
236.6, Poland 140.7, Slovenia 120.4, Italy 91.3, Greece 72.1.

The path was not steady. Croatian real wages fell in 2012–2014 (−3.4 %, −2.1 %, −5.2 %) and
were at 92.3 in 2015. The whole gain came after that.

```sql
SELECT country_code, round(real_wage_index_2010, 1) AS real_wage_index_2024, has_provisional
FROM analytics.v_real_wage_growth
WHERE year = 2024
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT', 'EL', 'BG')
ORDER BY real_wage_index_2010 DESC;

-- Position among the member states with data (Croatia: 12th of 26)
SELECT country_code, round(real_wage_index_2010, 1) AS real_wage_index_2024
FROM analytics.v_real_wage_growth
WHERE year = 2024 AND NOT is_aggregate
ORDER BY real_wage_index_2010 DESC NULLS LAST;

-- Croatia, year by year
SELECT year, round(real_wage_growth_pct, 1) AS real_growth, round(real_wage_index_2010, 1) AS idx
FROM analytics.v_real_wage_growth
WHERE country_code = 'HR'
ORDER BY year;
```

## 2. Croatia had higher inflation than the EU, but wages outpaced it; EU real wages fell

Croatian annual inflation was **10.7 % in 2022 and 8.4 % in 2023** (EU: 9.2 % and 6.4 %).
Over 2010–2025, consumer prices rose **48.9 % in Croatia** vs **42.8 % in the EU**. In 2024
Croatia had the 3rd-highest inflation among the 27 member states (rank 25 of 27, lower is
better).

Yet Croatian nominal wages rose **12.4 % (2022) and 13.4 % (2023)**, so real wages grew
**+1.6 % and +4.6 %**. EU real wages fell **−3.7 % and −0.2 %**, as did Slovenia's in 2022
(−3.5 %) and Italy's in both years (−4.7 %, −3.2 %).

```sql
SELECT country_code, year,
       round(nominal_wage_growth_pct, 1) AS nominal,
       round(inflation_pct, 1)           AS inflation,
       round(real_wage_growth_pct, 1)    AS real
FROM analytics.v_real_wage_growth
WHERE year IN (2022, 2023)
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT')
ORDER BY country_code, year;

-- Price level change 2010 -> 2025 (annual average HICP)
SELECT country_code,
       round(max(index_2015) FILTER (WHERE year = 2025)
             / max(index_2015) FILTER (WHERE year = 2010) * 100 - 100, 1) AS prices_up_pct_2010_2025
FROM analytics.v_index_base_2015
WHERE indicator_code = 'HICP_INDEX'
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT')
GROUP BY country_code
ORDER BY 2 DESC;

-- Croatia's ranks in 2024
SELECT indicator_code, country_rank, countries_ranked
FROM analytics.v_country_rank
WHERE country_code = 'HR' AND year = 2024
ORDER BY indicator_code;
```

## 3. Housing became less affordable: house prices doubled while wages rose two-thirds

Between 2015 and 2024, Croatian house prices rose **99.4 %** (index 199.4) and wages
**66.8 %** (166.8), so the **affordability ratio is 119.5**: house prices rose about 20 %
more than wages. The EU ratio is **115.2** (prices +53.4 %, wages +33.2 %). In 2025 Croatian
house prices rose another 13.9 % to **227.1** (2015 = 100). 2025 wages are not yet published.

Elsewhere: Portugal 149.5 (the least affordable), Hungary 128.1 (provisional), Slovenia 126.0,
Poland 104.7. In Italy (96.9) wages grew faster than house prices. Croatia ranks 18th of 25
(no data for Greece or the Netherlands).

```sql
SELECT country_code, year,
       round(house_price_index_2015, 1) AS hpi,
       round(wage_index_2015, 1)        AS wage,
       round(affordability_ratio, 1)    AS ratio,
       has_provisional
FROM analytics.v_housing_affordability
WHERE year = 2024
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT', 'PT', 'HU')
ORDER BY ratio DESC;

-- House prices in 2025, 2015 = 100
SELECT country_code, round(index_2015, 1) AS hpi_2025
FROM analytics.v_index_base_2015
WHERE indicator_code = 'HOUSE_PRICE_INDEX' AND year = 2025
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT', 'PT', 'HU')
ORDER BY 2 DESC;
```

## 4. Croatia is catching up: GDP per capita rose from 61 % to 78 % of the EU average

In purchasing power standards, Croatian GDP per capita went from **60.7 % of the EU average
in 2010** (61.4 % in 2015) to **77.6 % in 2025 (provisional)**. Most of the convergence
happened after 2015. Poland went from 63.3 % to 81.2 % and Slovenia from 83.2 % to 91.3 %.
Italy fell from 105.4 % to 96.1 %. These values match Eurostat's own published index
(`nama_10_pc`, unit `PC_EU27_2020_HAB_MPPS_CP`).

```sql
SELECT country_code, year, round(gdp_pc_index_eu27, 1) AS idx, has_provisional
FROM analytics.v_gdp_relative_to_eu
WHERE country_code IN ('HR', 'SI', 'PL', 'IT') AND year IN (2010, 2015, 2025)
ORDER BY country_code, year;
```

## 5. Unemployment in Croatia fell from 17.4 % (2013) to 4.9 % (2025), below the EU's 6.0 %

Croatian unemployment was 11.8 % in 2010 and peaked at **17.4 % in 2013** (EU: 11.6 %). By
**2025 it was 4.9 %**, below the **EU27 average of 6.0 %** (Slovenia 3.9 %, Poland 3.1 %,
Italy 6.0 %). Annual averages of 12 seasonally adjusted monthly rates.

```sql
SELECT country_code, year, round(value, 1) AS unemployment_rate
FROM analytics.v_annual_summary
WHERE indicator_code = 'UNEMPLOYMENT_RATE'
  AND country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT')
  AND year IN (2010, 2013, 2025)
ORDER BY country_code, year;
```

## 6. Net take-home pay: +25 % in real terms in Croatia (2013–2023), +5 % in the EU

For a single worker without children on the average wage, Croatian annual net earnings rose
from **€7,937 (2013) to €12,601 (2023)**: **+58.8 %** nominal against **+26.9 %** consumer
prices, which is **+25.1 % in real terms**. In the EU the increase was €21,324 → €28,324, or
**+4.6 % real**. Poland +36.1 %, Slovenia +15.9 %, Italy −1.9 %.

Caveats:
- The net earnings series for Croatia and the EU aggregate start in 2013, not 2010.
- It ends in 2023 because of the 2024 series break.
- It is in EUR, so for non-euro countries (Poland) it includes exchange-rate effects.
- Absolute levels show how far apart the countries still are: Croatian net pay is about 45 % of
  the EU figure.

```sql
WITH v AS (
    SELECT country_code,
           max(original_value) FILTER (WHERE indicator_code = 'NET_EARNINGS' AND year = 2013) AS net_2013,
           max(original_value) FILTER (WHERE indicator_code = 'NET_EARNINGS' AND year = 2023) AS net_2023,
           max(index_2015) FILTER (WHERE indicator_code = 'HICP_INDEX' AND year = 2013)       AS hicp_2013,
           max(index_2015) FILTER (WHERE indicator_code = 'HICP_INDEX' AND year = 2023)       AS hicp_2023
    FROM analytics.v_index_base_2015
    WHERE country_code IN ('HR', 'EU27_2020', 'SI', 'PL', 'IT')
    GROUP BY country_code
)
SELECT country_code,
       round(net_2013) AS net_2013_eur, round(net_2023) AS net_2023_eur,
       round((net_2023 / net_2013 - 1) * 100, 1)                             AS nominal_change_pct,
       round((hicp_2023 / hicp_2013 - 1) * 100, 1)                           AS price_change_pct,
       round(((net_2023 / net_2013) / (hicp_2023 / hicp_2013) - 1) * 100, 1) AS real_change_pct
FROM v
ORDER BY real_change_pct DESC;
```

---

## Caveats for the final write-up

- Wages are **gross** average full-time adjusted salaries (national accounts), not take-home
  pay. Real wages are deflated with the HICP, which covers consumer prices but **not owner-
  occupied housing costs**. That is why housing is a separate finding.
- The house price index measures purchase prices, not rents or mortgage costs (interest rates
  are not in the data).
- Real wage growth uses national currency; Croatia's series is in euro for all years
  (converted at the fixed kuna rate), so the 2023 euro changeover does not create a jump.
