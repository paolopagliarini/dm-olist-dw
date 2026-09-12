-- 00_schemas.sql
-- Three layers, three schemas:
--   staging    : raw CSV files loaded as-is (every column is TEXT), one table per file
--   reconciled : typed, cleaned and integrated data (the "reconciled layer" of the DW architecture)
--   dw         : the star schema (dimension tables + fact tables) queried by OLAP sessions
-- Re-running this file rebuilds everything from scratch.

DROP SCHEMA IF EXISTS dw CASCADE;
DROP SCHEMA IF EXISTS reconciled CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA reconciled;
CREATE SCHEMA dw;

-- unaccent() is used to normalise city names ('são paulo' -> 'sao paulo')
CREATE EXTENSION IF NOT EXISTS unaccent;
