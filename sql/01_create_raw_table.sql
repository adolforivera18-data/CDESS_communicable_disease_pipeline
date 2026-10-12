
-- ============================================================
-- 01_create_raw_table.sql
-- Purpose: Create the raw CDESS communicable disease table
-- Database: communicable_db_raw
-- Source: Amazon S3
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS
communicable_db_raw.raw_cdess_communicable_opencsv (
    case_year string,
    zip_code string,
    disease_name string,
    age string,
    age_units string,
    race_code string,
    white string,
    black string,
    american_indian string,
    asian string,
    pacific string,
    other_race string,
    unknown_race string,
    ethnicity_code string,
    ethnicity string,
    sex_code string,
    gender string,
    case_status string,
    geographic_area string
)
PARTITIONED BY (
    county_name string,
    extract_year string,
    extract_month string
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
    's3://publichealth-project-data-lake-152125350281-us-east-2-an/raw/ny-state/cdess/data_type=communicable/'
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);
