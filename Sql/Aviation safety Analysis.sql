/* ========================================================
   Analysis.sql   Each query answers one business question.
   ======================================================== */
USE AviationSafety;
GO

/* Q1. Is aviation getting safer? Civil accidents, fatalities and severity by decade. */
SELECT decade,
       COUNT(*) AS accidents,
       SUM(fatalities_total) AS fatalities,
       -- % change vs the previous decade (LAG looks at the previous row)
       CAST(100.0 * (SUM(fatalities_total) - LAG(SUM(fatalities_total)) OVER (ORDER BY decade))
            / LAG(SUM(fatalities_total)) OVER (ORDER BY decade) AS DECIMAL(6,1)) AS fatalities_pct_change,
       -- of events where fatalities are known, how many killed someone?
       CAST(100.0 * SUM(CASE WHEN fatalities_total > 0 THEN 1 ELSE 0 END)
            / COUNT(fatalities_total) AS DECIMAL(5,1)) AS pct_fatal_of_known,
       CAST(100.0 * SUM(CASE WHEN damage_level = 'Hull loss' THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,1)) AS pct_hull_loss
FROM dw.accidents
WHERE category_type = 'Accident' AND operator_type <> 'Military' AND event_year BETWEEN 1946 AND 2022
GROUP BY decade
ORDER BY decade
/* Findings:
   Fatalities rose to a peak of 17,793 in the 1970s and fell to 4,840 in the 2010s, while the number of
   accidents barely moved (1,764 -> 1,698). Fatal share of known events: 53.0% -> 22.6%. So accidents still happen
   about as often, but far fewer kill anyone.
   Hull-loss share fell 93.9% -> 57.4%, but ASN records more minor events in recent decades, so lead with fatalities. */


/* Q2. Which airlines had the most fatalities? (min. 10 accidents so tiny operators don't dominate) */
SELECT TOP 10 operator,
       COUNT(*) AS accidents,
       SUM(fatalities_total) AS fatalities
FROM dw.accidents
WHERE category_type = 'Accident' AND operator_type = 'Civil / Other' AND event_year BETWEEN 1946 AND 2022
GROUP BY operator
HAVING COUNT(*) >= 10
ORDER BY fatalities DESC
/* Findings: 
   The leaders are the largest, longest-running carriers: Air France 1,465 deaths (82 accidents),
   Pan Am 1,208, American 1,137, United 936, THY 900. */


/* Q3. How much of the raw data is military? */
SELECT decade,
       COUNT(*) AS all_events,
       SUM(CASE WHEN operator_type = 'Military' THEN 1 ELSE 0 END) AS military_events,
       CAST(100.0 * SUM(CASE WHEN operator_type = 'Military' THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,1)) AS military_pct
FROM dw.accidents
WHERE event_year BETWEEN 1910 AND 2022
GROUP BY decade
ORDER BY decade
/* Findings: 
   34.1% of the raw ASN records are military (78.3% in the 1940s, 45.4% in the 1950s, 8.4% in the 2010s).
   Without this filter the "crash trend" would mostly describe WWII. */


/* Q4. What causes civil accidents? */
SELECT era, cause_category,
       COUNT(*) AS accidents,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY era) AS DECIMAL(5,1)) AS pct_of_era
FROM dw.accidents
WHERE pci_matched = 1 AND operator_type <> 'Military' AND event_year BETWEEN 1946 AND 2022
GROUP BY era, cause_category
ORDER BY era, accidents DESC
/* Findings: 
   Mechanical (22-24%), terrain (20-22%) and weather (18-22%) are each about a fifth of civil accidents in
   every era, with no clear shift over time. 23-27% stay unclassified; human factors appear at only 6-8% because
   narratives rarely state pilot error outright, so the method undercounts it. */


/* Q5. Airline risk per unit of flying (airline-safety file, 1985-2014).
   Total seat-km flown = weekly capacity x 52 weeks x 15 years. */
WITH base AS (
    SELECT *, avail_seat_km_per_week * 52.0 * 15 / 1000000000 AS avail_seat_km_bn      -- billions of seat-km
    FROM dw.airline_safety
)
SELECT airline,
       fatalities_85_99, fatalities_00_14,
       CAST(fatalities_85_99 / avail_seat_km_bn AS DECIMAL(8,3)) AS fat_per_bn_85_99,
       CAST(fatalities_00_14 / avail_seat_km_bn AS DECIMAL(8,3)) AS fat_per_bn_00_14
FROM base
ORDER BY fat_per_bn_00_14 DESC
/* Findings:
   Highest 2000-14 rates: Kenya Airways 1.31, Malaysia Airlines 0.66, Gulf Air 0.61, China Airlines 0.36
   per billion seat-km. 32 of 56 airlines had zero fatalities in 2000-14. Highest in 1985-99: Avianca 1.04.
   Across all 56 airlines: fatal accidents fell 122 -> 37 and deaths 6,295 -> 3,109. */


/* Q6. Does the improvement continue after 2014? Fatal accidents per year for the mapped airlines:
   2000-14 (airline file) vs 2015-22 (ASN). */
WITH asn_events AS (
    SELECT m.airline, COUNT(DISTINCT a.accident_id) AS fatal_acc_15_22
    FROM dw.airline_map m
    JOIN dw.accidents a ON a.operator LIKE m.operator_pattern
    WHERE a.category_type = 'Accident' AND a.operator_type <> 'Military'
      AND a.fatalities_total > 0 AND a.event_year BETWEEN 2015 AND 2022
    GROUP BY m.airline
)
SELECT s.airline,
       s.fatal_acc_00_14,
       COALESCE(e.fatal_acc_15_22, 0) AS fatal_acc_15_22,
       CAST(s.fatal_acc_00_14 / 15.0 AS DECIMAL(5,2)) AS per_year_00_14,
       CAST(COALESCE(e.fatal_acc_15_22, 0) / 8.0 AS DECIMAL(5,2)) AS per_year_15_22
FROM dw.airline_safety s
LEFT JOIN asn_events e ON e.airline = s.airline
WHERE s.airline IN (SELECT airline FROM dw.airline_map)
ORDER BY s.fatal_acc_00_14 DESC
/* Findings:
   For the 17 mapped airlines, 16 fatal accidents in 2000-14 (1.07 per year) vs 3 in 2015-22 (0.38 per year:
   Aeroflot, Air India, Southwest). Counts are tiny, so this is consistent with continued improvement, not proof. */


/* Q7. Where did civil-aviation deaths concentrate? Top 10 countries. */
SELECT TOP 10 country,
       COUNT(*) AS accidents,
       SUM(fatalities_total) AS fatalities
FROM dw.accidents
WHERE category_type = 'Accident' AND operator_type <> 'Military' AND country IS NOT NULL
GROUP BY country
ORDER BY fatalities DESC
/* Findings: 
   USA 11,789 deaths (2,746 accidents), Russia 8,438, Colombia 2,896, Brazil 2,886, Indonesia 2,403.
   Fair to say, volume follows traffic volume; it is not a country safety ranking. */


/* Q8. Data-limits: how complete is each decade? */
SELECT decade,
       COUNT(*) AS events,
       SUM(CASE WHEN fatalities_total IS NULL THEN 1 ELSE 0 END) AS fatalities_unknown,
       SUM(pci_matched) AS with_narrative,
       CAST(100.0 * SUM(pci_matched) / COUNT(*) AS DECIMAL(5,1)) AS narrative_pct,
       SUM(CASE WHEN cause_category = 'Unclassified' THEN 1 ELSE 0 END) AS cause_unclassified
FROM dw.accidents
WHERE decade IS NOT NULL
GROUP BY decade
ORDER BY decade
/* Findings: Fatalities are unknown for 44% of 1940s events (2,554 of 5,768) but under 1% from 2000 on,
   so early-decade fatality totals are lower bounds, which makes the decline in Q1 conservative. Only 14.6% of all
   events have a narrative (8.3% in the 2010s), so cause analysis (Q4) rests on a subset skewed to older accidents. */