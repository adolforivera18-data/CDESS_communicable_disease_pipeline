# CDESS Communicable Disease Surveillance Pipeline

An AWS-based data engineering and public health surveillance project that transforms county-level Communicable Disease Electronic Surveillance System (CDESS) extracts into an interactive Amazon QuickSight dashboard for **Orange County, New York**.

The pipeline uses **Amazon S3**, **Amazon Athena**, **AWS Lambda**, and **Amazon QuickSight (SPICE)** to calculate annual communicable disease case counts and incidence rates per 100,000 population using **ACS 1-Year and ACS 5-Year** population estimates.

> **Data privacy:** Do not publish case-level CDESS extracts, restricted datasets, personal information, AWS access keys, or secrets in this repository. Publish only approved code, documentation, and appropriately reviewed dashboard screenshots.

## Project objectives

- Produce annual counts for confirmed and probable communicable disease cases.
- Group diseases by their classification and compare incidence across age, sex, and ethnicity.
- Calculate incidence rates per 100,000 using both ACS 1-Year and 5-Year population denominators.
- Support interactive exploration through a QuickSight dashboard.
- Refresh the curated dataset and QuickSight SPICE ingestion through a manually invoked Lambda function after annual source files are ready.

## Architecture

```text
CDESS CSV + disease classification CSV + ACS demographics CSV
                         |
                         v
                  Amazon S3 (raw/reference)
                         |
                         v
               Amazon Athena external tables
                         |
                         v
          AWS Lambda (manual annual invocation)
           |-- Repair CDESS table partitions
           |-- Drop previous curated Athena table
           |-- Delete previous curated S3 objects
           |-- Rebuild curated table via Athena CTAS
           `-- Start QuickSight SPICE ingestion
                         |
                         v
                Athena curated Parquet data
                         |
                         v
                Amazon QuickSight dashboard
```

**Note:** The Lambda invocation initiates the QuickSight ingestion; its successful response does **not** by itself mean the SPICE refresh has finished. Confirm completion in QuickSight refresh history.

## AWS components

| Component | Purpose |
| --- | --- |
| Amazon S3 | Store raw CDESS extracts, reference CSVs, and curated outputs |
| Amazon Athena | Query source/reference data and create the curated incidence table |
| AWS Lambda | Orchestrate the manual refresh workflow |
| Amazon QuickSight | Display surveillance metrics and interactive charts |
| QuickSight SPICE | Cache the curated dataset for dashboard use |

**AWS region:** `us-east-2`

### Athena databases and tables

| Database | Table | Role |
| --- | --- | --- |
| `communicable_db_raw` | `raw_cdess_communicable_opencsv` | CDESS source records |
| `communicable_db_reference` | `ref_disease_type_mapping` | Disease-to-type classification |
| `communicable_db_reference` | `ref_demographics` | ACS population denominators |
| `communicable_db_curated` | `communicable_disease_incidence` | Dashboard-ready annual counts and rates |

The raw CDESS table uses `OpenCSVSerde`, skips the CSV header, and is partitioned by `county_name`, `extract_year`, and `extract_month`.

## S3 layout

The following structure illustrates the project's data organization. Replace `<bucket>` with your configured bucket name.

```text
s3://<bucket>/
├── raw/ny-state/cdess/
│   └── data_type=communicable/
│       └── county_name=orange/
│           └── extract_year=YYYY/
│               └── extract_month=MM/
│                   └── <CDESS_extract>.csv
├── reference/ny-state/
│   ├── disease-classification/
│   └── demographics/
│       └── geography=orange-county/
├── curated/ny-state/cdess/
│   └── data_type=communicable/
│       └── incidence/
└── cdess/athena-results/
```

Each CDESS extract is a snapshot containing historical records. The transformation selects the **latest extract partition** to avoid counting the same cases multiple times across snapshots.

## Data preparation and transformation rules

### Critical CDESS preparation step

**Before uploading each new CDESS CSV to S3, add a `geographic_area` column and populate every row with `Orange County`.** Preserve the expected CSV column structure used by the Athena external table.

### Case inclusion and demographic rules

- Include `case_status = 1` (confirmed) and `case_status = 2` (probable).
- Use the latest available extract (`MAX(extract_year * 100 + extract_month)`).
- Age groups: `0-4`, `5-14`, `15-24`, `25-44`, `45-64`, `65-84`, `85+`.
- Treat ages over 110 as unknown; exclude unknown ages from age-group breakdowns.
- Do not use `age_units` or race fields in the current analysis.
- Use sex groups Female and Male; ethnicity groups Hispanic and Non-Hispanic.
- Include a separate `Total` demographic type/group in addition to the demographic breakdowns.
- Use the county-specific extract rather than ZIP-code filtering.
- Join disease names to the disease classification reference and demographic groups to ACS population denominators.

### Incidence formula

```text
Incidence rate per 100,000 = (case_count / population) * 100000
```

The curated output stores **separate rows** for ACS 1-Year and ACS 5-Year estimates; the same case count may therefore appear in both estimate types. Do not sum those duplicate case counts across estimate types.

### Curated table columns

| Column | Meaning |
| --- | --- |
| `disease_name` | CDESS disease name |
| `indicator_title` | Dashboard-friendly incidence indicator label |
| `disease_type` | Disease classification |
| `demographic_type` | `Total`, age, sex, or ethnicity |
| `demographic_group` | Group within the demographic type |
| `case_count` | Confirmed + probable cases |
| `estimate_type` | ACS 1-Year or ACS 5-Year |
| `population` | Population denominator for the estimate type |
| `incidence_rate` | Cases per 100,000 population |
| `geographic_area` | County/geographic label |
| `case_year` | Surveillance year |

The curated table is partitioned by `geographic_area` and `case_year`.

## Athena validation queries

Run these queries in the Athena query editor. They are intended for **quality assurance before and after an annual refresh**. Some queries may need small adjustments if reference-table column names change.

### 1. Preview the raw CDESS records

```sql
SELECT *
FROM communicable_db_raw.raw_cdess_communicable_opencsv
LIMIT 10;
```

Check that fields appear under the correct column names and values are not shifted.

### 2. Check CDESS partitions

```sql
SHOW PARTITIONS communicable_db_raw.raw_cdess_communicable_opencsv;
```

Verify the expected `county_name`, `extract_year`, and `extract_month` partitions exist. If newly uploaded partitions are missing, the Lambda workflow runs `MSCK REPAIR TABLE` to register them.

### 3. Identify the latest extract

```sql
SELECT county_name, extract_year, extract_month, COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
GROUP BY county_name, extract_year, extract_month
ORDER BY TRY_CAST(extract_year AS INTEGER) DESC,
         TRY_CAST(extract_month AS INTEGER) DESC;
```

Use this to confirm that the latest extract is available and has a plausible record count.

### 4. Validate the geographic area in the newest raw extract

```sql
WITH latest_extract AS (
    SELECT MAX(
        TRY_CAST(extract_year AS INTEGER) * 100
        + TRY_CAST(extract_month AS INTEGER)
    ) AS latest_yyyymm
    FROM communicable_db_raw.raw_cdess_communicable_opencsv
)
SELECT geographic_area, COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
CROSS JOIN latest_extract
WHERE TRY_CAST(extract_year AS INTEGER) * 100
    + TRY_CAST(extract_month AS INTEGER) = latest_yyyymm
GROUP BY geographic_area
ORDER BY record_count DESC;
```

**Expected:** All records in the new Orange County extract should show `Orange County`. If your raw Athena table does not yet expose `geographic_area`, update its schema to match the prepared CSV before running this check.

### 5. Review case-status distribution

```sql
SELECT case_status, COUNT(*) AS record_count
FROM communicable_db_raw.raw_cdess_communicable_opencsv
GROUP BY case_status
ORDER BY case_status;
```

The curated transformation includes only status codes `1` and `2`.

### 6. Check disease classification mapping totals

```sql
SELECT
    COUNT(*) AS mapping_rows,
    COUNT(DISTINCT disease_name) AS distinct_diseases,
    COUNT(DISTINCT disease_type) AS distinct_disease_types
FROM communicable_db_reference.ref_disease_type_mapping;
```

### 7. Find duplicate disease mapping entries

```sql
SELECT disease_name, COUNT(*) AS mapping_rows
FROM communicable_db_reference.ref_disease_type_mapping
GROUP BY disease_name
HAVING COUNT(*) > 1
ORDER BY mapping_rows DESC, disease_name;
```

**Expected:** Zero rows if each disease has exactly one classification mapping.

### 8. Find raw disease names missing from the mapping

```sql
SELECT DISTINCT r.disease_name
FROM communicable_db_raw.raw_cdess_communicable_opencsv r
LEFT JOIN communicable_db_reference.ref_disease_type_mapping m
    ON TRIM(UPPER(r.disease_name)) = TRIM(UPPER(m.disease_name))
WHERE m.disease_name IS NULL
ORDER BY r.disease_name;
```

Review and update the mapping reference before rebuilding the curated table. If the production SQL uses a different normalization rule, align this check with that rule.

### 9. Preview demographic reference data

```sql
SELECT *
FROM communicable_db_reference.ref_demographics
LIMIT 20;
```

Confirm that the annual ACS 1-Year and 5-Year denominators, demographic groups, geographic area, and year are represented as expected.

### 10. Review curated row counts by year and estimate type

```sql
SELECT
    case_year,
    estimate_type,
    COUNT(*) AS curated_rows
FROM communicable_db_curated.communicable_disease_incidence
GROUP BY case_year, estimate_type
ORDER BY case_year DESC, estimate_type;
```

Look for unexpectedly missing years or estimate types.

### 11. Check for null or invalid curated denominators

```sql
SELECT
    case_year,
    estimate_type,
    COUNT(*) AS invalid_rows
FROM communicable_db_curated.communicable_disease_incidence
WHERE population IS NULL
   OR population <= 0
GROUP BY case_year, estimate_type
ORDER BY case_year DESC, estimate_type;
```

**Expected:** Ideally zero rows; investigate any missing or invalid denominator.

### 12. Check for missing curated incidence rates

```sql
SELECT
    case_year,
    estimate_type,
    COUNT(*) AS missing_rate_rows
FROM communicable_db_curated.communicable_disease_incidence
WHERE incidence_rate IS NULL
GROUP BY case_year, estimate_type
ORDER BY case_year DESC, estimate_type;
```

Investigate missing rates and distinguish genuine denominator gaps from calculation errors.

### 13. Compare ACS estimate types without double-counting cases

```sql
SELECT
    disease_name,
    case_year,
    demographic_type,
    demographic_group,
    MAX(CASE WHEN estimate_type = '1-Year' THEN case_count END)
        AS cases_1_year,
    MAX(CASE WHEN estimate_type = '5-Year' THEN case_count END)
        AS cases_5_year
FROM communicable_db_curated.communicable_disease_incidence
GROUP BY disease_name, case_year, demographic_type, demographic_group
HAVING MAX(CASE WHEN estimate_type = '1-Year' THEN case_count END)
    <> MAX(CASE WHEN estimate_type = '5-Year' THEN case_count END)
ORDER BY case_year DESC, disease_name;
```

**Expected:** Zero rows where both estimate types are available, because ACS estimate selection changes the population denominator, not the number of cases. **Check the exact `estimate_type` labels in your curated data** and adjust `'1-Year'` / `'5-Year'` if necessary.

### 14. Preview curated results for a disease

```sql
SELECT
    disease_name,
    disease_type,
    case_year,
    demographic_type,
    demographic_group,
    estimate_type,
    case_count,
    population,
    incidence_rate,
    geographic_area
FROM communicable_db_curated.communicable_disease_incidence
WHERE disease_name = 'AMEBIASIS'
ORDER BY case_year DESC, demographic_type, demographic_group, estimate_type
LIMIT 100;
```

Use a known disease as a spot check of case counts, demographic groups, and calculated incidence rates.

### 15. Recalculate incidence rates to check arithmetic

```sql
SELECT
    disease_name,
    case_year,
    demographic_type,
    demographic_group,
    estimate_type,
    case_count,
    population,
    incidence_rate,
    ROUND(100000.0 * case_count / NULLIF(population, 0), 2)
        AS recalculated_rate
FROM communicable_db_curated.communicable_disease_incidence
WHERE population > 0
  AND ABS(
      incidence_rate - (100000.0 * case_count / population)
  ) > 0.02
ORDER BY case_year DESC, disease_name
LIMIT 100;
```

**Expected:** Zero rows, allowing for minor rounding differences.

## QuickSight dashboard

The dashboard supports:

- Disease type selection and a dependent disease/indicator selection.
- ACS estimate selection: 1-Year, 5-Year, or both.
- Demographic type and demographic group controls.
- Annual incidence line charts with demographic and ACS estimate series.
- Year-by-year pivot comparisons and a detailed surveillance table.
- A disease distribution chart showing each disease's share of cases within the selected disease type.
- A data sources and methodology section.

The line chart uses a calculated series label combining demographic group and ACS estimate type, so users can compare both dimensions in the same visualization.

## Manual annual update procedure

The refresh is **intentionally manual** because the publication dates of the CDESS and ACS source datasets are not predictable.

1. Obtain the new county-specific CDESS communicable disease CSV.
2. **Add `geographic_area` with the value `Orange County` to every CDESS row before uploading to S3.**
3. Verify that the prepared CSV retains the expected columns, order, and formatting.
4. Upload the CDESS extract to its new `extract_year=YYYY/extract_month=MM/` S3 partition.
5. Update the Orange County demographic reference CSV in its established S3 location, preserving its schema.
6. Update the disease classification mapping CSV if new diseases or classifications require it.
7. Run the relevant Athena validation queries above, especially partition, geography, mapping, and demographic checks.
8. Open AWS Lambda and invoke `communicable-disease-pipeline-refresh` with the existing `{}` test event. **The handler must be `lambda_function.lambda_handler`.**
9. Check Lambda execution logs for success. The workflow repairs partitions, drops the previous curated table, deletes its S3 objects, rebuilds it with Athena CTAS, and starts a QuickSight SPICE ingestion.
10. Confirm the QuickSight **refresh history** reports **Completed**; an ingestion request that is merely `INITIALIZED` is not finished.
11. Run the curated validation queries and spot-check dashboard visuals and filters.

> **Operational caution:** The current Lambda refresh drops and replaces the existing curated table and deletes its existing S3 output before recreating it. Only invoke the full handler when the required source and reference files have been prepared and validated. A failed rebuild can temporarily leave the curated dataset unavailable.

## Latest verified run

On **October 10, 2026**, the Athena rebuild stage completed and a separately invoked QuickSight SPICE refresh completed successfully:

- **4,126 rows imported**
- **0 rejected rows**
- **2 minutes, 26 seconds** for the QuickSight full refresh

The QuickSight refresh was verified after an IAM permission fix. The full Lambda sequence was not rerun end-to-end after that fix; the Athena and QuickSight stages were successfully tested separately.

## Repository contents (planned)

```text
CDESS_communicable_disease_pipeline/
├── README.md
├── sql/                 # Athena DDL, CTAS, and validation SQL
├── lambda/              # Pipeline orchestration Python source
├── docs/                # Architecture and methodology
└── screenshots/         # Approved, non-sensitive dashboard images
```

Only publish the actual, reviewed source files when adding these folders. Replace account-specific identifiers, internal paths, and any sensitive values with safe configuration placeholders as appropriate.

## Limitations and future enhancements

- Data availability and completeness depend on the CDESS extract and ACS reference releases.
- Missing or incomplete demographic information can affect demographic-specific counts and rates.
- ACS 1-Year and 5-Year estimates provide different denominators and can yield different incidence rates for the same case count.
- The pipeline is manually triggered rather than scheduled.
- Future improvements could include automated validation gates, narrower IAM permissions, ingestion-status polling, safer atomic publication of curated outputs, and multi-county support.

## Data sources and methodology

- County-specific CDESS communicable disease extracts (authorized access; not included in this repository).
- Disease classification reference mapping maintained for this project.
- American Community Survey (ACS) 1-Year and 5-Year population estimates for Orange County, New York.

This repository documents a public health analytics engineering workflow. Its outputs should be interpreted in the context of source-system reporting practices, data completeness, and population-estimate limitations.
