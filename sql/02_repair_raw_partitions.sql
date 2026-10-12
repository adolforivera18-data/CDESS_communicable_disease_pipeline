
-- ============================================================
-- 02_repair_raw_partitions.sql
-- Purpose: Register and verify raw CDESS S3 partitions
-- Database: communicable_db_raw
-- Run after creating the raw table or adding new partitions
-- ============================================================

-- Step 1: Discover and register S3 partitions
MSCK REPAIR TABLE communicable_db_raw.raw_cdess_communicable_opencsv;

-- Step 2: Verify registered partitions
SHOW PARTITIONS communicable_db_raw.raw_cdess_communicable_opencsv;
