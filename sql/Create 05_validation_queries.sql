
-- ============================================================
-- 05_validation_queries.sql
-- Project: CDESS Communicable Disease Surveillance Pipeline
-- Purpose: Validate raw, reference, and curated datasets
--
-- Run each query separately in Amazon Athena.
-- These are read-only validation queries.
-- ============================================================


-- ============================================================
-- 01. Preview raw CDESS records
-- ============================================================

SELECT *
FROM communicable_db_raw.raw_cdess_communicable_opencsv
LIMIT 10;


-- ============================================================
-- 02. Verify registered S3 partitions
-- ============================================================

SHOW PARTITIONS communicable_db_raw.raw_cdess_communicable_opencsv;


-- ============================================================
-- 03. Count raw records by extract partition
-- ============================================================

SELECT
    county_name,
    extract_year,
    extract_month,
    COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
GROUP BY
    county_name,
    extract_year,
    extract_month
ORDER BY
    extract_year DESC,
    extract_month DESC;


-- ============================================================
-- 04. Verify geographic_area values
-- ============================================================

SELECT
    geographic_area,
    COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
GROUP BY geographic_area
ORDER BY record_count DESC;


-- ============================================================
-- 05. Verify case status distribution
-- ============================================================

SELECT
    case_status,
    COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
GROUP BY case_status
ORDER BY case_status;


-- ============================================================
-- 06. Validate disease classification reference
-- ============================================================

SELECT
    COUNT(*) AS mapping_rows,
    COUNT(DISTINCT disease_name) AS unique_diseases,
    COUNT(DISTINCT disease_type) AS unique_disease_types
FROM communicable_db_reference.ref_disease_type_mapping;


-- ============================================================
-- 07. Identify unmapped diseases in the latest extract
-- ============================================================

WITH latest_extract AS (
    SELECT MAX(
        TRY_CAST(extract_year AS INTEGER) * 100
        + TRY_CAST(extract_month AS INTEGER)
    ) AS latest_yyyymm
    FROM communicable_db_raw.raw_cdess_communicable_opencsv
)

SELECT
    TRIM(c.disease_name) AS disease_name,
    COUNT(*) AS case_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv c
CROSS JOIN latest_extract le
LEFT JOIN communicable_db_reference.ref_disease_type_mapping d
    ON TRIM(c.disease_name) = TRIM(d.disease_name)
WHERE
    TRY_CAST(c.case_status AS INTEGER) IN (1, 2)
    AND (
        TRY_CAST(c.extract_year AS INTEGER) * 100
        + TRY_CAST(c.extract_month AS INTEGER)
    ) = le.latest_yyyymm
    AND d.disease_name IS NULL
GROUP BY TRIM(c.disease_name)
ORDER BY case_count DESC;


-- ============================================================
-- 08. Preview demographic reference data
-- ============================================================

SELECT *
FROM communicable_db_reference.ref_demographics
LIMIT 20;


-- ============================================================
-- 09. Validate population estimates by year
-- ============================================================

SELECT
    year,
    geographic_area,
    estimate_type,
    population
FROM communicable_db_reference.ref_demographics
WHERE LOWER(TRIM(demographic_type)) = 'total'
  AND LOWER(TRIM(demographic_group)) = 'total'
ORDER BY year, estimate_type;


-- ============================================================
-- 10. Check missing demographic population values
-- ============================================================

SELECT
    year,
    demographic_type,
    demographic_group,
    estimate_type
FROM communicable_db_reference.ref_demographics
WHERE TRY_CAST(population AS BIGINT) IS NULL
   OR TRY_CAST(population AS BIGINT) <= 0;


-- ============================================================
-- 11. Preview curated incidence dataset
-- ============================================================

SELECT *
FROM communicable_db_curated.communicable_disease_incidence
LIMIT 20;


-- ============================================================
-- 12. Validate curated records by year and ACS estimate
-- ============================================================

SELECT
    case_year,
    estimate_type,
    COUNT(*) AS record_count
FROM communicable_db_curated.communicable_disease_incidence
GROUP BY case_year, estimate_type
ORDER BY case_year, estimate_type;


-- ============================================================
-- 13. Identify missing incidence denominators or rates
-- ============================================================

SELECT
    disease_name,
    case_year,
    demographic_type,
    demographic_group,
    estimate_type,
    case_count,
    population,
    incidence_rate
FROM communicable_db_curated.communicable_disease_incidence
WHERE population IS NULL
   OR population <= 0
   OR incidence_rate IS NULL
ORDER BY case_year, disease_name;


-- ============================================================
-- 14. Verify incidence rate calculations
-- Rates are per 100,000 population.
-- ============================================================

SELECT
    disease_name,
    case_year,
    demographic_type,
    demographic_group,
    estimate_type,
    case_count,
    population,
    incidence_rate,

    ROUND(
        CAST(case_count AS DOUBLE)
        / NULLIF(CAST(population AS DOUBLE), 0)
        * 100000,
        2
    ) AS recalculated_rate

FROM communicable_db_curated.communicable_disease_incidence
WHERE population > 0
LIMIT 100;


-- ============================================================
-- 15. Check for duplicate curated dimension combinations
-- Expected result: zero rows
-- ============================================================

SELECT
    disease_name,
    disease_type,
    demographic_type,
    demographic_group,
    estimate_type,
    geographic_area,
    case_year,
    COUNT(*) AS duplicate_count

FROM communicable_db_curated.communicable_disease_incidence

GROUP BY
    disease_name,
    disease_type,
    demographic_type,
    demographic_group,
    estimate_type,
    geographic_area,
    case_year

HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
