
-- ============================================================
-- 04_create_curated_incidence.sql
-- Project: CDESS Communicable Disease Surveillance Pipeline
--
-- Purpose:
-- Transform raw CDESS communicable disease records into
-- a curated, population-adjusted incidence dataset.
--
-- Processing:
--   1. Select the latest CDESS extract.
--   2. Include confirmed and probable cases (status 1, 2).
--   3. Standardize age, sex, and ethnicity groups.
--   4. Join disease classification reference data.
--   5. Calculate case counts by demographic group.
--   6. Join ACS 1-Year and 5-Year population estimates.
--   7. Calculate incidence rates per 100,000 population.
--   8. Convert incidence rates into long format.
--   9. Write partitioned Parquet data to Amazon S3.
--
-- Output:
-- communicable_db_curated.communicable_disease_incidence
--
-- Partition columns:
-- geographic_area, case_year
--
-- Note:
-- The target table must not already exist, and the target
-- S3 output prefix must be empty before running this CTAS.
-- The Lambda pipeline handles both preparation steps.
-- ============================================================
CREATE TABLE communicable_db_curated.communicable_disease_incidence
WITH (
    format = 'PARQUET',
    external_location = 's3://publichealth-project-data-lake-152125350281-us-east-2-an/curated/ny-state/cdess/data_type=communicable/incidence/',
    partitioned_by = ARRAY['geographic_area', 'case_year']
)
AS

WITH latest_extract AS (

    SELECT
        MAX(
            TRY_CAST(extract_year AS INTEGER) * 100
            + TRY_CAST(extract_month AS INTEGER)
        ) AS latest_extract_yyyymm

    FROM communicable_db_raw.raw_cdess_communicable_opencsv
),

eligible_cases AS (

    SELECT
        TRIM(c.geographic_area) AS geographic_area,
        TRY_CAST(c.case_year AS INTEGER) AS case_year,
        TRIM(c.disease_name) AS disease_name,
        TRIM(d.disease_type) AS disease_type,

        CASE
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 0 AND 4 THEN '0-4'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 5 AND 14 THEN '5-14'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 15 AND 24 THEN '15-24'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 25 AND 44 THEN '25-44'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 45 AND 64 THEN '45-64'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 65 AND 84 THEN '65-84'
            WHEN TRY_CAST(c.age AS INTEGER) BETWEEN 85 AND 110 THEN '85+'
            ELSE NULL
        END AS age_group,

        CASE
            WHEN LOWER(TRIM(c.gender)) = 'female' THEN 'Female'
            WHEN LOWER(TRIM(c.gender)) = 'male' THEN 'Male'
            ELSE NULL
        END AS sex_group,

        CASE
            WHEN LOWER(TRIM(c.ethnicity)) = 'hispanic or latino' THEN 'Hispanic'
            WHEN LOWER(TRIM(c.ethnicity)) = 'non-hispanic or latino' THEN 'Non-Hispanic'
            ELSE NULL
        END AS ethnicity_group

    FROM communicable_db_raw.raw_cdess_communicable_opencsv c

    CROSS JOIN latest_extract le

    LEFT JOIN communicable_db_reference.ref_disease_type_mapping d
        ON TRIM(c.disease_name) = TRIM(d.disease_name)

    WHERE
        TRY_CAST(c.case_status AS INTEGER) IN (1, 2)
        AND (
            TRY_CAST(c.extract_year AS INTEGER) * 100
            + TRY_CAST(c.extract_month AS INTEGER)
        ) = le.latest_extract_yyyymm
),

stratified_counts AS (

    -- Total
    SELECT
        disease_name,
        disease_type,
        'Total' AS demographic_type,
        'Total' AS demographic_group,
        COUNT(*) AS case_count,
        geographic_area,
        case_year
    FROM eligible_cases
    GROUP BY
        disease_name,
        disease_type,
        geographic_area,
        case_year

    UNION ALL

    -- Age
    SELECT
        disease_name,
        disease_type,
        'age' AS demographic_type,
        age_group AS demographic_group,
        COUNT(*) AS case_count,
        geographic_area,
        case_year
    FROM eligible_cases
    WHERE age_group IS NOT NULL
    GROUP BY
        disease_name,
        disease_type,
        age_group,
        geographic_area,
        case_year

    UNION ALL

    -- Sex
    SELECT
        disease_name,
        disease_type,
        'sex' AS demographic_type,
        sex_group AS demographic_group,
        COUNT(*) AS case_count,
        geographic_area,
        case_year
    FROM eligible_cases
    WHERE sex_group IS NOT NULL
    GROUP BY
        disease_name,
        disease_type,
        sex_group,
        geographic_area,
        case_year

    UNION ALL

    -- Ethnicity
    SELECT
        disease_name,
        disease_type,
        'ethnicity' AS demographic_type,
        ethnicity_group AS demographic_group,
        COUNT(*) AS case_count,
        geographic_area,
        case_year
    FROM eligible_cases
    WHERE ethnicity_group IS NOT NULL
    GROUP BY
        disease_name,
        disease_type,
        ethnicity_group,
        geographic_area,
        case_year
),

denominators AS (

    SELECT
        LOWER(TRIM(geographic_area)) AS geographic_area,
        TRY_CAST(year AS INTEGER) AS year,
        LOWER(TRIM(demographic_type)) AS demographic_type,
        LOWER(TRIM(demographic_group)) AS demographic_group,

        MAX(
            CASE
                WHEN LOWER(TRIM(estimate_type)) LIKE '%1%year%'
                THEN TRY_CAST(population AS BIGINT)
            END
        ) AS population_1_year,

        MAX(
            CASE
                WHEN LOWER(TRIM(estimate_type)) LIKE '%5%year%'
                THEN TRY_CAST(population AS BIGINT)
            END
        ) AS population_5_year

    FROM communicable_db_reference.ref_demographics

    GROUP BY
        LOWER(TRIM(geographic_area)),
        TRY_CAST(year AS INTEGER),
        LOWER(TRIM(demographic_type)),
        LOWER(TRIM(demographic_group))
),

wide_rates AS (

    SELECT
        c.disease_name,

        CONCAT(
            c.disease_name,
            ' Incidence Rate per 100,000'
        ) AS indicator_title,

        c.disease_type,
        c.demographic_type,
        c.demographic_group,
        c.case_count,

        d.population_1_year,

        ROUND(
            (
                CAST(c.case_count AS DOUBLE)
                /
                NULLIF(CAST(d.population_1_year AS DOUBLE), 0)
            ) * 100000,
            2
        ) AS incidence_rate_1_year,

        d.population_5_year,

        ROUND(
            (
                CAST(c.case_count AS DOUBLE)
                /
                NULLIF(CAST(d.population_5_year AS DOUBLE), 0)
            ) * 100000,
            2
        ) AS incidence_rate_5_year,

        c.geographic_area,
        c.case_year

    FROM stratified_counts c

    LEFT JOIN denominators d
        ON LOWER(TRIM(c.geographic_area)) = d.geographic_area
        AND c.case_year = d.year
        AND LOWER(TRIM(c.demographic_type)) = d.demographic_type
        AND LOWER(TRIM(c.demographic_group)) = d.demographic_group
),

long_rates AS (

    -- ACS 1-Year
    SELECT
        disease_name,
        indicator_title,
        disease_type,
        demographic_type,
        demographic_group,
        case_count,

        '1-Year' AS estimate_type,
        population_1_year AS population,
        incidence_rate_1_year AS incidence_rate,

        geographic_area,
        case_year

    FROM wide_rates

    UNION ALL

    -- ACS 5-Year
    SELECT
        disease_name,
        indicator_title,
        disease_type,
        demographic_type,
        demographic_group,
        case_count,

        '5-Year' AS estimate_type,
        population_5_year AS population,
        incidence_rate_5_year AS incidence_rate,

        geographic_area,
        case_year

    FROM wide_rates
)

SELECT
    disease_name,
    indicator_title,
    disease_type,
    demographic_type,
    demographic_group,
    case_count,
    estimate_type,
    population,
    incidence_rate,
    geographic_area,
    case_year

FROM long_rates
