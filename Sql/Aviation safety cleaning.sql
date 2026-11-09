/* =============================================================================
   Cleaning.sql   (stg.* -> dw.asn_clean, dw.pci_clean, dw.airline_safety)
   Goal: turn the raw text columns into usable types WITHOUT losing information.
   ============================================================================= */
USE AviationSafety
GO

/* ---------- 1. ASN (main accident list) ---------- */
DROP TABLE IF EXISTS dw.asn_clean;

WITH dedup AS (
    SELECT DISTINCT * 
    FROM stg.asn      -- exact duplicates only
)
SELECT
    IDENTITY(INT, 1, 1) AS accident_id,
    TRY_CONVERT(date, date_raw) AS event_date,     -- NULL if partial / unknown
    TRY_CAST(year_raw AS INT) AS event_year,    
    NULLIF(TRIM(aircraft_type), '') AS aircraft_type,
    UPPER(REPLACE(NULLIF(TRIM(registration), ''), '-', '')) AS registration_key,
    NULLIF(TRIM(operator), '') AS operator,
    NULLIF(TRIM(location), '') AS location,
    NULLIF(NULLIF(TRIM(country), ''), 'Unknown country') AS country,
    cat AS cat_code,
    TRY_CAST(CASE WHEN fatalities LIKE '%+%'
                  THEN LEFT(fatalities, CHARINDEX('+', fatalities) - 1)
                  ELSE fatalities 
             END AS INT) AS fat_occupants,  -- NULL = unknown (NOT zero)
    CASE WHEN fatalities LIKE '%+%'
         THEN TRY_CAST(SUBSTRING(fatalities, CHARINDEX('+', fatalities) + 1, 10) AS INT)
    END AS fat_ground
INTO dw.asn_clean
FROM dedup
GO

/* ---------- 2. PCI (planecrashinfo: narrative summaries) ---------- */
DROP TABLE IF EXISTS dw.pci_clean;

WITH cleaned AS (
    SELECT
        TRY_CONVERT(date, Date) AS event_date,
        UPPER(REPLACE(NULLIF(NULLIF(TRIM(Registration), '?'), ''), '-', '')) AS registration_key,
        NULLIF(TRIM(route), '?') AS route,
        TRY_CAST(LEFT(Aboard, CHARINDEX(' ', Aboard + ' ') - 1) AS INT) AS aboard_total,
        NULLIF(TRIM(REPLACE(Summary, CHAR(13), '')), '') AS summary
    FROM stg.pci
)
SELECT *,
       ROW_NUMBER() OVER (PARTITION BY event_date, registration_key ORDER BY summary) AS rn   -- rn = 1 -> keep, avoids duplicate joins
INTO dw.pci_clean
FROM cleaned
GO

/* ---------- 3. Airline safety (exposure data) ---------- */
DROP TABLE IF EXISTS dw.airline_safety;

SELECT
    TRIM(REPLACE(airline, '*', '')) AS airline,          -- '*' = includes regional subsidiaries
    CASE WHEN airline LIKE '%*' THEN 1 ELSE 0 END AS includes_regional,
    CAST(avail_seat_km_per_week AS BIGINT) AS avail_seat_km_per_week,     -- available seat-km per week = airline size
    CAST(incidents_85_99 AS INT) AS incidents_85_99,
    CAST(fatal_accidents_85_99 AS INT) AS fatal_acc_85_99,
    CAST(fatalities_85_99 AS INT) AS fatalities_85_99,
    CAST(incidents_00_14 AS INT) AS incidents_00_14,
    CAST(fatal_accidents_00_14 AS INT) AS fatal_acc_00_14,
    CAST(REPLACE(fatalities_00_14, CHAR(13), '') AS INT) AS fatalities_00_14  -- strip the CRLF left by the CSV
INTO dw.airline_safety
FROM stg.airline_safety

/* Issues fixed:
       1. ASN has 115 exact duplicate rows                        -> SELECT DISTINCT
       2. ASN dates are text ('07-DEC-2005'; some partial/unknown) -> TRY_CONVERT (bad dates become NULL)
       3. ASN fatalities are text, 'N' or 'N+ G' (N on board + G on ground) -> split with CHARINDEX
       4. PCI uses '?' for missing values                          -> NULLIF
       5. PCI has repeated date+registration pairs                 -> keep the first record only */


/* ---------- 4. Cleaning audit: copy these numbers into your README ---------- */
USE AviationSafety;
GO

SELECT 'ASN rows loaded'                   AS metric, COUNT(*) AS value FROM stg.asn
UNION ALL SELECT 'ASN rows after dedup',              COUNT(*) FROM dw.asn_clean
UNION ALL SELECT 'ASN with no full date',             COUNT(*) FROM dw.asn_clean WHERE event_date IS NULL
UNION ALL SELECT 'ASN with unknown fatalities',       COUNT(*) FROM dw.asn_clean WHERE fat_occupants IS NULL
UNION ALL SELECT 'PCI rows',                          COUNT(*) FROM dw.pci_clean
UNION ALL SELECT 'PCI rows kept for joining (rn=1)',  COUNT(*) FROM dw.pci_clean WHERE rn = 1 AND registration_key IS NOT NULL AND event_date IS NOT NULL