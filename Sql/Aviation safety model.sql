/* ==============================================================================
   Model.sql   (dw.asn_clean + dw.pci_clean -> dw.accidents, dw.airline_map)
   Design decision: One flat reporting table, one row per accident (~23.9k rows).
   =============================================================================*/
USE AviationSafety;
GO

DROP TABLE IF EXISTS dw.accidents;

SELECT
    a.accident_id,
    a.event_date,
    a.event_year,
    a.event_year / 10 * 10 AS decade,
    CASE WHEN a.event_year <= 1945 THEN '1) Up to 1945'
         WHEN a.event_year <= 1969 THEN '2) 1946-1969'
         WHEN a.event_year <= 1999 THEN '3) 1970-1999'
         WHEN a.event_year >= 2000 THEN '4) 2000+'
         ELSE 'Unknown' END AS era,
    a.aircraft_type,
    a.operator,

    -- Who was flying? ASN mixes military, private and airline flights.
      
    CASE WHEN a.operator IS NULL THEN 'Unknown'
         WHEN a.operator IN ('USAF', 'RAF', 'USAAF', 'US Navy', 'RAAF', 'RCAF', 'USMC')
           OR a.operator LIKE '%Air Force%' OR a.operator LIKE '%Navy%' OR a.operator LIKE '%Army%'
           OR a.operator LIKE '%Military%'  OR a.operator LIKE '% AF' OR a.operator LIKE '% AF,%'
              THEN 'Military'
         WHEN a.operator = 'private' THEN 'Private'
         ELSE 'Civil / Other'
    END AS operator_type,

    a.country,

    /* ASN category code: letter = event type, digit = damage (1 = hull loss, 2 = repairable) */
    CASE LEFT(a.cat_code, 1) WHEN 'A' THEN 'Accident'  WHEN 'I' THEN 'Incident'
                             WHEN 'H' THEN 'Hijacking' WHEN 'C' THEN 'Criminal occurrence'
                             WHEN 'O' THEN 'Other'     ELSE 'Unknown' END AS category_type,
    CASE RIGHT(a.cat_code, 1) WHEN '1' THEN 'Hull loss' WHEN '2' THEN 'Repairable damage'
                              ELSE 'Not applicable' END AS damage_level,

    a.fat_occupants,
    a.fat_ground,
    CASE WHEN a.fat_occupants IS NULL THEN NULL
         ELSE a.fat_occupants + COALESCE(a.fat_ground, 0) END AS fatalities_total,   -- NULL stays unknown

    /* Narrative data from planecrashinfo (only available where date + registration matched) */
    CASE WHEN p.event_date IS NULL THEN 0 ELSE 1 END     AS pci_matched,
    p.route,
    p.aboard_total,
    p.summary,

    /* Cause bucket from keywords in the summary. First matching rule wins, so the order matters:
       Hostile -> Terrain -> Weather -> Mechanical -> Human factors. */
    CASE WHEN p.event_date IS NULL THEN NULL
         WHEN p.summary LIKE '%shot down%' OR p.summary LIKE '%missile%' OR p.summary LIKE '%bomb%'
           OR p.summary LIKE '%hijack%'    OR p.summary LIKE '%sabotage%' OR p.summary LIKE '%terror%'
              THEN 'Hostile / Criminal'
         WHEN p.summary LIKE '%mountain%'  OR p.summary LIKE '%hillside%' OR p.summary LIKE '%terrain%'
           OR p.summary LIKE '%struck trees%' OR p.summary LIKE '%high ground%'
              THEN 'Terrain / Obstacle'
         WHEN p.summary LIKE '%fog%'  OR p.summary LIKE '%storm%' OR p.summary LIKE '%icing%'
           OR p.summary LIKE '%snow%' OR p.summary LIKE '%turbulence%' OR p.summary LIKE '%wind shear%'
           OR p.summary LIKE '%visibility%' OR p.summary LIKE '%lightning%' OR p.summary LIKE '%weather%'
              THEN 'Weather'
         WHEN p.summary LIKE '%engine%' OR p.summary LIKE '%mechanical%' OR p.summary LIKE '%fatigue%'
           OR p.summary LIKE '%structural%' OR p.summary LIKE '%malfunction%' OR p.summary LIKE '%hydraulic%'
           OR p.summary LIKE '%fuel%' OR p.summary LIKE '%fire%' OR p.summary LIKE '%electrical%'
              THEN 'Mechanical / Technical'
         WHEN p.summary LIKE '%pilot error%' OR p.summary LIKE '%crew error%' OR p.summary LIKE '%collid%'
           OR p.summary LIKE '%mid-air%' OR p.summary LIKE '%stall%' OR p.summary LIKE '%disorient%'
           OR p.summary LIKE '%overran%' OR p.summary LIKE '%overshot%' OR p.summary LIKE '%miscalculat%'
              THEN 'Human factors / Operations'
         ELSE 'Unclassified' END                        AS cause_category
INTO dw.accidents
FROM dw.asn_clean a
LEFT JOIN dw.pci_clean p
       ON  p.event_date = a.event_date
       AND p.registration_key    = a.registration_key
       AND p.rn = 1                                   -- one narrative per date + registration -> no duplicated rows
GO


/* ---------- Airline lookup: safety-file name -> ASN operator-name pattern ----------
   Lets us extend the 1985-2014 airline file with ASN events from 2015-2022.
   Seeded with 17 well-known airlines; extend the rest the same way. */
DROP TABLE IF EXISTS dw.airline_map;
CREATE TABLE dw.airline_map (airline NVARCHAR(100), operator_pattern NVARCHAR(100));
INSERT INTO dw.airline_map VALUES
 ('aeroflot', 'Aeroflot%'), ('lufthansa', 'Lufthansa%'), ('klm', 'KLM%'), ('air france', 'Air France%'),
 ('british airways', 'British Airways%'), ('qantas', 'Qantas%'), ('air canada', 'Air Canada%'),
 ('air india', 'Air India%'), ('korean air', 'Korean Air%'), ('singapore airlines', 'Singapore Airlines%'),
 ('turkish airlines', 'Turkish Airlines%'), ('southwest airlines', 'Southwest Airlines%'),
 ('cathay pacific', 'Cathay Pacific%'), ('american', 'American Airlines%'), ('american', 'American Eagle%'),
 ('delta / northwest', 'Delta Air Lines%'), ('delta / northwest', 'Delta Connection%'),
 ('delta / northwest', 'Northwest Airlines%'), ('delta / northwest', 'Northwest Orient%'),
 ('united / continental', 'United Airlines%'), ('united / continental', 'United Express%'),
 ('united / continental', 'Continental Air Lines%'), ('united / continental', 'Continental Express%'),
 ('us airways / america west', 'USAir%'), ('us airways / america west', 'US Airways%'),
 ('us airways / america west', 'America West%');
 GO

/*--------- Airline Trend View ------------*/
CREATE OR ALTER VIEW dw.vw_airline_trend AS
SELECT s.airline, s.fatal_acc_00_14,
       COALESCE(e.fatal_acc_15_22, 0) AS fatal_acc_15_22
FROM dw.airline_safety s
LEFT JOIN (
    SELECT m.airline, COUNT(DISTINCT a.accident_id) AS fatal_acc_15_22
    FROM dw.airline_map m
    JOIN dw.accidents a ON a.operator LIKE m.operator_pattern
    WHERE a.category_type = 'Accident' AND a.operator_type <> 'Military'
      AND a.fatalities_total > 0 AND a.event_year BETWEEN 2015 AND 2022
    GROUP BY m.airline) e ON e.airline = s.airline
WHERE s.airline IN (SELECT airline FROM dw.airline_map)