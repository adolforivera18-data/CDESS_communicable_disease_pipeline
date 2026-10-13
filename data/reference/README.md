# Reference Data

This directory contains the reference datasets used by the **CDESS Communicable Disease Surveillance Pipeline** for Orange County, New York.

These datasets support disease classification, demographic stratification, and the calculation of annual communicable disease incidence rates per 100,000 population.

## Reference Datasets

### 1. Disease Classification Mapping

**File:** `disease_classification.csv` (use the actual uploaded filename)

**Purpose:** Maps communicable disease names from CDESS to standardized disease categories for reporting and visualization.

| Column | Description |
|---|---|
| `disease_name` | Disease name corresponding to the CDESS source dataset |
| `disease_type` | Disease classification or reporting category |

**Athena table:** `communicable_db_reference.ref_disease_type_mapping`

**S3 location:**
`s3://publichealth-project-data-lake-152125350281-us-east-2-an/reference/ny-state/disease-classification/`

The disease classification mapping is joined to the raw CDESS dataset using `disease_name`. It allows the QuickSight dashboard to filter and compare diseases by category.

The mapping should be reviewed whenever new diseases appear in a CDESS extract.

### 2. Demographic Population Reference

**File:** `demographic_reference_orange_county_2024.csv`

**Purpose:** Provides population denominators used to calculate annual communicable disease incidence rates for Orange County, New York.

The dataset includes American Community Survey (ACS) 1-Year and 5-Year population estimates.

| Column | Description |
|---|---|
| `geographic_area` | Geographic location, currently Orange County |
| `year` | Population estimate year |
| `demographic_type` | Total, age, sex, or ethnicity |
| `demographic_group` | Specific demographic category |
| `population` | Estimated population |
| `source` | Source of the population estimate |
| `estimate_type` | ACS 1-Year or 5-Year |

**Athena table:** `communicable_db_reference.ref_demographics`

**S3 location:**
`s3://publichealth-project-data-lake-152125350281-us-east-2-an/reference/ny-state/demographics/geography=orange-county/`

The demographic reference dataset supports incidence calculations for the total population and demographic subgroups.

Age groups used by the pipeline are:

- 0–4
- 5–14
- 15–24
- 25–44
- 45–64
- 65–84
- 85+

Sex categories are Female and Male. Ethnicity categories are Hispanic and Non-Hispanic.

## Incidence Rate Calculation

Annual incidence rates are calculated using:

**Incidence Rate = (Case Count / Population) × 100,000**

The pipeline calculates separate rates using ACS 1-Year and ACS 5-Year population denominators, allowing comparisons between the two population estimates.

If a corresponding population denominator is unavailable, the incidence rate remains null.

## Reference Data Maintenance

Reference datasets are maintained separately from the raw CDESS case-level exports.

**Annual demographic update:**

1. Obtain updated ACS population estimates.
2. Prepare the demographic reference CSV using the existing column structure and demographic group definitions.
3. Verify that `geographic_area` is populated with `Orange County`.
4. Validate the population estimates and their corresponding years.
5. Replace the demographic reference CSV in its existing S3 location, ensuring that obsolete CSV versions are not left alongside the replacement.
6. Run the AWS Lambda pipeline refresh after all source datasets have been updated.
7. Validate the resulting Athena incidence table and QuickSight SPICE refresh.

**Disease classification update:**

Review the disease mapping when new disease names appear in CDESS extracts. Add or update classifications as needed before running the pipeline.

## Data Quality Considerations

- Disease names must match between the CDESS dataset and the classification mapping.
- Demographic categories must align with the categories used by the Athena transformation.
- Population estimates must be associated with the correct geographic area and year.
- ACS 1-Year and 5-Year estimates are maintained separately.
- Missing or invalid population denominators should be investigated before interpreting incidence rates.

## Data Sources

- **Communicable Disease Electronic Surveillance System (CDESS):** Disease surveillance records used by the pipeline.
- **U.S. Census Bureau — American Community Survey (ACS):** Population estimates used as incidence rate denominators.
- **Disease classification mapping:** Project-maintained reference mapping for grouping communicable diseases into reporting categories.

## Related SQL Scripts

The SQL definitions and validation queries for these reference datasets are located in the repository's `sql/` directory:

- `03_create_reference_tables.sql`
- `05_validation_queries.sql`

The reference files are used by the curated incidence transformation defined in `04_create_curated_incidence.sql`.
