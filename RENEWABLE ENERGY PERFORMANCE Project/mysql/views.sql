-- =====================================================================================
-- views.sql   (run this THIRD, after schema.sql and insert_data.sql)
-- Project folder : D:\RENEWABLE ENERGY PERFORMANCE Project
--
-- A VIEW is a saved SELECT query. It works like a table, but the result is calculated
-- when we ask for it. Power BI connects to these views (Get Data > MySQL database).
--
--   vw_energy_full          all 4 tables joined, one row per record
--   vw_plant_performance    one row per plant: KPIs, Performance Score, rank and class
--   vw_energy_type_summary  Solar vs Wind vs Hydro
--   vw_monthly_summary      one row per month and energy type
--   vw_downtime_summary     downtime and the energy / money lost, one row per plant
--   vw_weather_bands        average utilization for each weather band
-- =====================================================================================

USE renewable_energy_analytics;

-- -------------------------------------------------------------------------------------
-- 1. vw_energy_full : the detail table, one row per plant per 4-hour block
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_energy_full AS
SELECT  e.Record_ID,
        p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region, p.City, p.Installed_Capacity_MW,
        e.Date,
        YEAR(e.Date)      AS Year_No,
        MONTH(e.Date)     AS Month_No,
        MONTHNAME(e.Date) AS Month_Name,
        e.Hour,
        e.Energy_Generated_MWh, e.Capacity_Utilization, e.Efficiency_Percent, e.Availability_Percent,
        w.Temperature_C, w.Wind_Speed_kmh, w.Solar_Irradiance, w.Rainfall_mm,
        m.Downtime_Hours, m.Maintenance_Hours, m.Plant_Status,
        e.Operating_Cost, m.Maintenance_Cost, e.Revenue,
        e.Operating_Cost + m.Maintenance_Cost AS Total_Cost,
        e.Revenue - e.Operating_Cost - m.Maintenance_Cost AS Profit
FROM    Energy_Generation e
INNER JOIN Plants p              ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w        ON w.Record_ID = e.Record_ID
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID;

-- -------------------------------------------------------------------------------------
-- 2. vw_plant_performance : derived metrics + Plant Performance Score
--    Score = 30% utilization + 25% efficiency + 20% availability + 15% cost (lower is better)
--            + 10% profit margin; every component scaled 0-100 WITHIN its energy type.
--    Class : top quarter = High, bottom quarter = Low, rest = Medium.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_plant_performance AS
WITH plant_metrics AS (
    SELECT  p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region, p.City, p.Installed_Capacity_MW,
            COUNT(*)                                   AS Records,
            COUNT(DISTINCT e.Date)                     AS Days_Covered,
            SUM(e.Energy_Generated_MWh)                AS Total_Energy_MWh,
            SUM(e.Energy_Generated_MWh) / COUNT(DISTINCT e.Date) AS Avg_Daily_Generation_MWh,
            SUM(e.Energy_Generated_MWh) / (p.Installed_Capacity_MW * 4 * COUNT(*)) * 100 AS Capacity_Utilization_Rate,
            AVG(e.Efficiency_Percent)                  AS Plant_Efficiency_Rate,
            AVG(e.Availability_Percent)                AS Plant_Availability_Rate,
            SUM(m.Downtime_Hours)                      AS Total_Downtime_Hours,
            SUM(m.Downtime_Hours) / (4 * COUNT(*)) * 100 AS Downtime_Rate,
            SUM(m.Maintenance_Hours)                   AS Total_Maintenance_Hours,
            SUM(e.Operating_Cost)                      AS Operating_Cost,
            SUM(m.Maintenance_Cost)                    AS Maintenance_Cost,
            SUM(e.Revenue)                             AS Revenue
    FROM    Plants p
    INNER JOIN Energy_Generation e   ON e.Plant_ID  = p.Plant_ID
    INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
    GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region, p.City, p.Installed_Capacity_MW
),
plant_kpis AS (
    SELECT  pm.*,
            (Operating_Cost + Maintenance_Cost) / Total_Energy_MWh AS Cost_per_MWh,
            Revenue / Total_Energy_MWh                             AS Revenue_per_MWh,
            Maintenance_Cost / Total_Energy_MWh                    AS Maintenance_Cost_per_MWh,
            (Revenue - Operating_Cost - Maintenance_Cost) / Revenue * 100 AS Profit_Margin_Pct
    FROM    plant_metrics pm
),
scaled AS (
    SELECT  k.*,
            COALESCE((Capacity_Utilization_Rate - MIN(Capacity_Utilization_Rate) OVER w)
                     / NULLIF(MAX(Capacity_Utilization_Rate) OVER w - MIN(Capacity_Utilization_Rate) OVER w, 0) * 100, 50) AS CU_Score,
            COALESCE((Plant_Efficiency_Rate - MIN(Plant_Efficiency_Rate) OVER w)
                     / NULLIF(MAX(Plant_Efficiency_Rate) OVER w - MIN(Plant_Efficiency_Rate) OVER w, 0) * 100, 50) AS Efficiency_Score,
            COALESCE((Plant_Availability_Rate - MIN(Plant_Availability_Rate) OVER w)
                     / NULLIF(MAX(Plant_Availability_Rate) OVER w - MIN(Plant_Availability_Rate) OVER w, 0) * 100, 50) AS Availability_Score,
            COALESCE(100 - (Cost_per_MWh - MIN(Cost_per_MWh) OVER w)
                     / NULLIF(MAX(Cost_per_MWh) OVER w - MIN(Cost_per_MWh) OVER w, 0) * 100, 50) AS Cost_Score,
            COALESCE((Profit_Margin_Pct - MIN(Profit_Margin_Pct) OVER w)
                     / NULLIF(MAX(Profit_Margin_Pct) OVER w - MIN(Profit_Margin_Pct) OVER w, 0) * 100, 50) AS Margin_Score
    FROM    plant_kpis k
    WINDOW  w AS (PARTITION BY Energy_Type)
),
scored AS (
    SELECT  s.*,
            0.30 * CU_Score + 0.25 * Efficiency_Score + 0.20 * Availability_Score
          + 0.15 * Cost_Score + 0.10 * Margin_Score AS Performance_Score
    FROM    scaled s
)
SELECT  sc.*,
        RANK() OVER (ORDER BY Performance_Score DESC)                          AS Rank_Overall,
        RANK() OVER (PARTITION BY Energy_Type ORDER BY Performance_Score DESC) AS Rank_in_Type,
        CASE NTILE(4) OVER (ORDER BY Performance_Score DESC, Plant_ID)
             WHEN 1 THEN 'High'
             WHEN 4 THEN 'Low'
             ELSE 'Medium' END                                                 AS Performance_Class
FROM    scored sc;

-- -------------------------------------------------------------------------------------
-- 3. vw_energy_type_summary : Solar vs Wind vs Hydro
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_energy_type_summary AS
SELECT  p.Energy_Type,
        COUNT(DISTINCT p.Plant_ID)                        AS Plants,
        tc.Installed_Capacity_MW,
        SUM(e.Energy_Generated_MWh)                       AS Total_Energy_MWh,
        AVG(e.Energy_Generated_MWh)                       AS Avg_Energy_per_Record_MWh,
        SUM(e.Energy_Generated_MWh) / (tc.Installed_Capacity_MW * COUNT(DISTINCT e.Date) * 24) * 100 AS Capacity_Utilization_Rate,
        AVG(e.Efficiency_Percent)                         AS Avg_Efficiency_Pct,
        AVG(e.Availability_Percent)                       AS Avg_Availability_Pct,
        SUM(e.Revenue)                                    AS Revenue,
        SUM(e.Operating_Cost)                             AS Operating_Cost,
        SUM(m.Maintenance_Cost)                           AS Maintenance_Cost,
        (SUM(e.Operating_Cost) + SUM(m.Maintenance_Cost)) / SUM(e.Energy_Generated_MWh) AS Cost_per_MWh,
        SUM(e.Revenue) / SUM(e.Energy_Generated_MWh)      AS Revenue_per_MWh,
        (SUM(e.Revenue) - SUM(e.Operating_Cost) - SUM(m.Maintenance_Cost)) / SUM(e.Revenue) * 100 AS Profit_Margin_Pct
FROM    Energy_Generation e
INNER JOIN Plants p              ON p.Plant_ID  = e.Plant_ID
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
INNER JOIN (SELECT Energy_Type, SUM(Installed_Capacity_MW) AS Installed_Capacity_MW
            FROM Plants GROUP BY Energy_Type) tc ON tc.Energy_Type = p.Energy_Type
GROUP BY p.Energy_Type, tc.Installed_Capacity_MW;

-- -------------------------------------------------------------------------------------
-- 4. vw_monthly_summary : one row per month and energy type
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT  DATE_SUB(e.Date, INTERVAL DAY(e.Date) - 1 DAY) AS Month_Start,
        YEAR(e.Date)      AS Year_No,
        MONTH(e.Date)     AS Month_No,
        MONTHNAME(e.Date) AS Month_Name,
        p.Energy_Type,
        SUM(e.Energy_Generated_MWh)                    AS Energy_MWh,
        SUM(e.Energy_Generated_MWh) / (tc.Installed_Capacity_MW * DAY(LAST_DAY(MIN(e.Date))) * 24) * 100 AS Capacity_Utilization_Rate,
        AVG(e.Efficiency_Percent)                      AS Avg_Efficiency_Pct,
        AVG(e.Availability_Percent)                    AS Avg_Availability_Pct,
        SUM(m.Downtime_Hours)                          AS Downtime_Hours,
        SUM(e.Revenue)                                 AS Revenue,
        SUM(e.Operating_Cost)                          AS Operating_Cost,
        SUM(m.Maintenance_Cost)                        AS Maintenance_Cost,
        (SUM(e.Operating_Cost) + SUM(m.Maintenance_Cost)) / SUM(e.Energy_Generated_MWh) AS Cost_per_MWh,
        SUM(e.Revenue) / SUM(e.Energy_Generated_MWh)   AS Revenue_per_MWh
FROM    Energy_Generation e
INNER JOIN Plants p              ON p.Plant_ID  = e.Plant_ID
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
INNER JOIN (SELECT Energy_Type, SUM(Installed_Capacity_MW) AS Installed_Capacity_MW
            FROM Plants GROUP BY Energy_Type) tc ON tc.Energy_Type = p.Energy_Type
GROUP BY Month_Start, Year_No, Month_No, Month_Name, p.Energy_Type, tc.Installed_Capacity_MW;

-- -------------------------------------------------------------------------------------
-- 5. vw_downtime_summary : downtime, status mix and the energy lost to downtime
--    Estimated loss = Energy / (Availability/100) - Energy for blocks that were at least partly
--    available. Fully shut-down blocks are excluded, so this is a minimum estimate.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_downtime_summary AS
SELECT  p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region,
        SUM(m.Downtime_Hours)                                       AS Total_Downtime_Hours,
        SUM(m.Downtime_Hours) / (4 * COUNT(*)) * 100                AS Downtime_Rate,
        SUM(m.Maintenance_Hours)                                    AS Total_Maintenance_Hours,
        SUM(m.Plant_Status = 'Operational')                         AS Operational_Blocks,
        SUM(m.Plant_Status = 'Partial Outage')                      AS Partial_Outage_Blocks,
        SUM(m.Plant_Status = 'Under Maintenance')                   AS Under_Maintenance_Blocks,
        SUM(m.Plant_Status = 'Shutdown')                            AS Shutdown_Blocks,
        SUM(CASE WHEN e.Availability_Percent > 0
                 THEN e.Energy_Generated_MWh / (e.Availability_Percent / 100) - e.Energy_Generated_MWh
                 ELSE 0 END)                                        AS Est_Energy_Lost_MWh,
        SUM(CASE WHEN e.Availability_Percent > 0
                 THEN e.Energy_Generated_MWh / (e.Availability_Percent / 100) - e.Energy_Generated_MWh
                 ELSE 0 END) * SUM(e.Revenue) / SUM(e.Energy_Generated_MWh) / 10000000 AS Est_Revenue_Lost_INR_Crore
FROM    Plants p
INNER JOIN Energy_Generation e   ON e.Plant_ID  = p.Plant_ID
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region;

-- -------------------------------------------------------------------------------------
-- 6. vw_weather_bands : average utilization by weather band
--    Solar : irradiance bands, daytime blocks only (start hours 8 and 12)
--    Wind  : wind-speed bands
--    Hydro : monsoon (Jun-Sep) vs rest of the year
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_weather_bands AS
SELECT  'Solar' AS Energy_Type, 'Irradiance (W/m2), daytime' AS Driver,
        CASE WHEN w.Solar_Irradiance < 200 THEN '1) under 200'
             WHEN w.Solar_Irradiance < 400 THEN '2) 200-400'
             WHEN w.Solar_Irradiance < 600 THEN '3) 400-600'
             WHEN w.Solar_Irradiance < 800 THEN '4) 600-800'
             ELSE '5) 800 and above' END AS Band,
        COUNT(*) AS Records,
        AVG(e.Capacity_Utilization)    AS Avg_Capacity_Utilization_Pct,
        AVG(e.Energy_Generated_MWh)    AS Avg_Energy_MWh
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
WHERE   p.Energy_Type = 'Solar' AND e.Hour IN (8, 12)
GROUP BY Band
UNION ALL
SELECT  'Wind', 'Wind speed (km/h)',
        CASE WHEN w.Wind_Speed_kmh < 10 THEN '1) under 10'
             WHEN w.Wind_Speed_kmh < 20 THEN '2) 10-20'
             WHEN w.Wind_Speed_kmh < 30 THEN '3) 20-30'
             WHEN w.Wind_Speed_kmh < 40 THEN '4) 30-40'
             WHEN w.Wind_Speed_kmh < 50 THEN '5) 40-50'
             ELSE '6) 50 and above' END,
        COUNT(*), AVG(e.Capacity_Utilization), AVG(e.Energy_Generated_MWh)
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
WHERE   p.Energy_Type = 'Wind'
GROUP BY 3
UNION ALL
SELECT  'Hydro', 'Season',
        CASE WHEN MONTH(e.Date) BETWEEN 6 AND 9 THEN '2) Monsoon (Jun-Sep)' ELSE '1) Rest of year' END,
        COUNT(*), AVG(e.Capacity_Utilization), AVG(e.Energy_Generated_MWh)
FROM    Energy_Generation e
INNER JOIN Plants p ON p.Plant_ID = e.Plant_ID
WHERE   p.Energy_Type = 'Hydro'
GROUP BY 3;
