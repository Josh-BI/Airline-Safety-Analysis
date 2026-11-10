# Aviation Safety Risk Analysis: Is Civil Aviation Getting Safer?

An end-to-end analytics project on real, publicly scraped aviation accident data from 1908 to 2023 obtained via Kaggle: SQL Server for cleaning and modelling, Power BI for a five-page dashboard.

> **Role played:** safety and risk analyst advising an insurer or regulator. Where does aviation risk concentrate, has it changed over time, and how far can the data be trusted?

![Executive summary](Preview%20Images/Executive%20summary.png)

## Key findings

All figures cover **civil accidents, 1946-2022**, unless stated.

| # | Finding |
|---|---|
| 1 | **Fatalities fell sharply while accident counts stayed flat.** Deaths peaked at 17,793 in the 1970s and fell to 4,840 in the 2010s (**-73%**). Accidents barely moved (1,764 to 1,698). The share of events with known fatalities that were fatal fell from 53.0% to 22.6%. |
| 2 | **About 34% of the raw data is military.** It was 78% in the 1940s and 8% in the 2010s. Without filtering it out, "crash trends" mostly describe WWII(World War 2). |
| 3 | **Raw counts mislead.** The top operators by deaths are the largest and oldest carriers (Air France 1,465; Pan Am 1,208; American 1,137), so risk is normalized by flying done (seat-km). |
| 4 | **Normalized risk (2000-14):** Kenya Airways (1.31 deaths per billion seat-km), Malaysia Airlines (0.66), Gulf Air (0.61). 32 of 56 airlines had zero fatalities. Fatal accidents across all 56 fell from 122 to 37. Rankings are driven by one or two events (Malaysia's 537 deaths are MH17 and MH370). |
| 5 | **After 2014, the trend continues.** The 17 airlines mapped to ASN averaged 1.07 fatal accidents per year in 2000-14 and 0.38 in 2015-22 (16 vs 3 events). The counts are small, so this is consistent with improvement, not proof. |
| 6 | **Causes are stable across eras.** Mechanical, terrain and weather each explain roughly 20 to 25% of accidents. 25.7% are unclassified and human factors show only 7.5%, so the keyword method undercounts pilot-related causes. Indicative only. |

### Recommendations

1. **Track severity, not just frequency.** Fatal share and fatalities per accident show the improvement that accident counts hide.
2. **Always normalize by exposure** (seat-km or flights) before ranking operators or countries.
3. **Improve cause coding.** Only about 15% of events have a narrative and human factors are under recorded, so structured cause fields would make this analysis far more stronger.

## Dashboard

| Page | Question | Preview |
|---|---|---|
| 1. Executive summary | Is civil aviation getting safer? | ![Executive summary](Preview%20Images/Executive%20summary.png) |
| 2. Where it happens | Which operators and countries have the most fatalities? | ![Where it happens](Preview%20Images/Where%20it%20happens.png) |
| 3. Airline risk | Who is riskier per unit of flying? | ![Airline risk](Preview%20Images/Airline%20risk.png) |
| 4. Causes | What causes civil accidents? | ![Causes](Preview%20Images/Causes.png)|
| 5. Data limits | How far can we trust the data? | ![Data limits](Preview%20Images/Data%20limits.png) |

## Data sources

| File | Source | Rows | Used for |
|---|---|---|---|
| `aviation-accident-data-2023-05-16.csv` | [Aviation Safety Network](https://aviation-safety.net) via Kaggle ([civil-aviation-accidents](https://www.kaggle.com/datasets/warcoder/civil-aviation-accidents)) | 23,967 | Main fact table: date, aircraft, operator, country, category, fatalities |
| `accident_details_compiled.csv` | [planecrashinfo.com](https://www.planecrashinfo.com) via Kaggle ([airplane-crash-data-since-1908](https://www.kaggle.com/datasets/cgurkan/airplane-crash-data-since-1908)) | 5,078 | Narrative summaries and routes (cause analysis) |
| `airline-safety.csv` | [FiveThirtyEight](https://datahub.io/fivethirtyeight/airline-safety) | 56 airlines | Exposure (seat-km per week) to normalise risk |


## Tech stack

**SQL:** staging, cleaning, modelling, and exploratory analysis.  
**Power BI:** DAX measures and five-page report.

## Repository structure

```
.
├── Data raw/              
├── Power BI/
│   └── Aviation Safety Risk Analysis.pbix
├── Preview Images
├── Sql/
│   ├── cleaning.sql       
│   ├── model.sql         
│   └── analysis.sql
├── data clean/
└── README.md
```

### Key cleaning and modelling decisions

| Issue or choice | Decision | Why |
|---|---|---|
| 115 exact duplicate rows in ASN | `SELECT DISTINCT` on raw rows | Removes true duplicates only |
| Text dates, some partial (`??-DEC-1928`) | `TRY_CONVERT`, with year kept separately | Year is known far more often than the full date |
| Fatalities stored as text (`N` or `N+ G`) | Split into occupants and ground deaths | Total = occupants + ground |
| 16% of fatalities missing | Kept as `NULL`, never zero | Zero would bias every rate downward |
| ~34% of records are military | Name-based flag, excluded from trend pages | Keeps the analysis about civil aviation |
| Narratives exist for only some events | `LEFT JOIN` on date + registration, one narrative per key | Row count verified unchanged after the join |
| Cause categories | Ordered keyword `CASE` on narratives (first match wins) | Transparent and editable; unclassified share is reported |
| Star schema vs one table | One flat table | About 24k rows at a single grain, so extra dimensions only add joins |

### SQL techniques used

`CTE`, `SELECT DISTINCT`, `TRY_CAST` / `TRY_CONVERT`, `CASE`, `CHARINDEX` / `SUBSTRING`, `LEFT JOIN`, `ROW_NUMBER()` for de-duplication, `LAG()` for decade-over-decade change, `SUM() OVER (PARTITION BY ...)` for percentage shares, conditional aggregation, and `HAVING`.

### Analysis queries

| Query | Question |
|---|---|
| Query 1 | Civil accidents, fatalities and severity by decade |
| Query 2 | Top operators by fatalities (minimum 10 accidents) |
| Query 3 | Military share of the raw data by decade |
| Query 4 | Cause mix by era |
| Query 5 | Airline risk per billion seat-km |
| Query 6 | Airline fatal accidents per year, 2000-14 vs 2015-22 |
| Query 7 | Top countries by fatalities |
| Query 8 | Data completeness by decade |

### Power BI measures (examples)

```dax
Accidents       = COUNTROWS(dw.accidents)
Fatalities      = SUM(dw.accidents[fatalities_total])
% Fatal of Known =
    DIVIDE(CALCULATE(COUNTROWS(accidents), accidents[fatalities_total] > 0),
           COUNT(accidents[fatalities_total]))          -- COUNT skips NULL = unknown
Fat per Bn ASK 00-14 =
    DIVIDE(SUM(airline_safety[fatalities_00_14]),
           SUM(airline_safety[ask_per_week]) * 52 * 15 / 1000000000)
```

**Page scope (Pages 1, 2 and 4):** `category_type = Accident`, `operator_type is not Military`, `event_year` 1946 to 2022.

## Limitations

- **Survivorship and reporting bias:** the sources lean toward notable and fatal events, and recording of minor incidents has grown over time. The fall in hull-loss share (94% to 57%) is partly due to this.
- **Unknown fatalities:** 44% of 1940s events have none recorded, so early totals are lower bounds. That makes the decline conservative.
- **Military flag** is a name-based heuristic and may misclassify a few operators.
- **Cause analysis** covers only about 15% of events (those with a narrative) and uses keywords, so it undercounts human factors. Best treated as indicative.
- **Airline risk** assumes constant capacity over each 15-year period, and rankings are dominated by a few events.
- **Partial decades:** the 1940s row covers 1946-49 and the 2020s row covers 2020-22.
- **Source encoding:** some operator names contain garbled characters in the original file and were left as is.


## Possible extensions

- Extend the data past mid-2023 with a Python scraper.
- Normalise by flights or passenger-km for the post-2014 period.
- Replace the keyword causes with official investigation causes where available.
