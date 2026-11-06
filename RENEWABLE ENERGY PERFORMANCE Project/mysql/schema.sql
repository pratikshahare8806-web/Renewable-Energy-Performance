-- =====================================================================================
-- schema.sql   (run this FIRST)
-- Project folder : D:\RENEWABLE ENERGY PERFORMANCE Project
--
-- What this file does
--   1. Makes the database  renewable_energy_analytics
--   2. Makes 4 tables:  Plants, Energy_Generation, Weather_Data, Maintenance_Records
--   (The tables are empty after this file. The next file, insert_data.sql, puts the data in.)
--
-- Why 4 tables?  Plant details never change, so they are stored once (Plants).
-- The other 3 tables have one row per record and are connected with Record_ID.
--
-- Run order:  schema.sql  ->  insert_data.sql  ->  views.sql  ->  queries.sql
-- =====================================================================================

DROP DATABASE IF EXISTS renewable_energy_analytics;
CREATE DATABASE renewable_energy_analytics
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE renewable_energy_analytics;

-- -------------------------------------------------------------------------------------
-- 1. Plants : one row per plant (master data)
-- -------------------------------------------------------------------------------------
CREATE TABLE Plants (
    Plant_ID              CHAR(4)                        NOT NULL,
    Plant_Name            VARCHAR(60)                    NOT NULL,
    Energy_Type           ENUM('Solar','Wind','Hydro')   NOT NULL,
    Region                VARCHAR(10)                    NOT NULL,
    City                  VARCHAR(40)                    NOT NULL,
    Installed_Capacity_MW DECIMAL(8,2)                   NOT NULL,
    PRIMARY KEY (Plant_ID)
) ENGINE=InnoDB;

-- -------------------------------------------------------------------------------------
-- 2. Energy_Generation : one row per plant per 4-hour block (generation, performance, money)
-- -------------------------------------------------------------------------------------
CREATE TABLE Energy_Generation (
    Record_ID             CHAR(7)        NOT NULL,
    Plant_ID              CHAR(4)        NOT NULL,
    Date                  DATE           NOT NULL,
    Hour                  TINYINT        NOT NULL COMMENT 'Start hour of the 4-hour block: 0,4,8,12,16,20',
    Energy_Generated_MWh  DECIMAL(12,3)  NOT NULL,
    Capacity_Utilization  DECIMAL(6,2)   NOT NULL COMMENT 'Percent',
    Efficiency_Percent    DECIMAL(6,2)   NOT NULL,
    Availability_Percent  DECIMAL(6,2)   NOT NULL,
    Operating_Cost        DECIMAL(16,2)  NOT NULL COMMENT 'INR',
    Revenue               DECIMAL(16,2)  NOT NULL COMMENT 'INR',
    PRIMARY KEY (Record_ID),
    KEY idx_gen_plant (Plant_ID),
    KEY idx_gen_date  (Date),
    CONSTRAINT fk_gen_plant FOREIGN KEY (Plant_ID) REFERENCES Plants (Plant_ID),
    CONSTRAINT chk_gen_hour CHECK (Hour IN (0,4,8,12,16,20))
) ENGINE=InnoDB;

-- -------------------------------------------------------------------------------------
-- 3. Weather_Data : weather at the plant for the same record
-- -------------------------------------------------------------------------------------
CREATE TABLE Weather_Data (
    Record_ID         CHAR(7)       NOT NULL,
    Temperature_C     DECIMAL(5,1)  NOT NULL,
    Wind_Speed_kmh    DECIMAL(6,1)  NOT NULL,
    Solar_Irradiance  DECIMAL(7,1)  NOT NULL COMMENT 'W/m2',
    Rainfall_mm       DECIMAL(6,1)  NOT NULL,
    PRIMARY KEY (Record_ID),
    CONSTRAINT fk_weather_record FOREIGN KEY (Record_ID) REFERENCES Energy_Generation (Record_ID)
) ENGINE=InnoDB;

-- -------------------------------------------------------------------------------------
-- 4. Maintenance_Records : downtime, maintenance and status for the same record
-- -------------------------------------------------------------------------------------
CREATE TABLE Maintenance_Records (
    Record_ID          CHAR(7)       NOT NULL,
    Downtime_Hours     DECIMAL(4,2)  NOT NULL,
    Maintenance_Hours  DECIMAL(4,2)  NOT NULL,
    Plant_Status       ENUM('Operational','Partial Outage','Under Maintenance','Shutdown') NOT NULL,
    Maintenance_Cost   DECIMAL(16,2) NOT NULL COMMENT 'INR',
    PRIMARY KEY (Record_ID),
    KEY idx_maint_status (Plant_Status),
    CONSTRAINT fk_maint_record FOREIGN KEY (Record_ID) REFERENCES Energy_Generation (Record_ID),
    CONSTRAINT chk_downtime CHECK (Downtime_Hours BETWEEN 0 AND 4)
) ENGINE=InnoDB;

-- Check: the 4 tables exist (they are empty until you run insert_data.sql)
SHOW TABLES;
