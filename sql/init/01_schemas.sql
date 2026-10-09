-- Create the three pipeline layers. Runs once, on first start of the DB container.

CREATE SCHEMA IF NOT EXISTS raw;        -- data exactly as received from Eurostat
CREATE SCHEMA IF NOT EXISTS warehouse;  -- star schema (dimensions + fact table)
CREATE SCHEMA IF NOT EXISTS analytics;  -- views consumed by Power BI
