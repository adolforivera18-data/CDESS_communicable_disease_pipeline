
-- ============================================================
-- 03_create_reference_tables.sql
-- Purpose: Create the Athena reference database and tables
-- Project: CDESS Communicable Disease Surveillance Pipeline
-- ============================================================

-- Step 1: Create the reference database
CREATE DATABASE IF NOT EXISTS communicable_db_reference;


-- ============================================================
-- Step 2: Disease Classification Reference Table
-- Maps disease_name to disease_type
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS
communicable_db_reference.ref_disease_type_mapping (
    disease_name string,
    disease_type string
)
ROW FORMAT SERDE
    'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION
    's3://publichealth-project-data-lake-152125350281-us-east-2-an/reference/ny-state/disease-classification/'
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);


-- ============================================================
-- Step 3: Demographic Reference Table
-- Contains ACS 1-Year and 5-Year population estimates
-- for Orange County, New York
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS
communicable_db_reference.ref_demographics (
    geographic_area string,
    year string,
    demographic_type string,
    demographic_group string,
    population string,
    source string,
    estimate_type string
)
ROW FORMAT SERDE
    'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar' = '"',
    'escapeChar' = '\\'
)
STORED AS TEXTFILE
LOCATION
    's3://publichealth-project-data-lake-152125350281-us-east-2-an/reference/ny-state/demographics/geography=orange-county/'
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);
