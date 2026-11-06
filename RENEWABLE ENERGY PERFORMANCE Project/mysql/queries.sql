-- =====================================================================================
-- queries.sql   (run this FOURTH, after schema.sql, insert_data.sql and views.sql)
-- Project folder : D:\RENEWABLE ENERGY PERFORMANCE Project
--
-- Each query answers one business question. Read the comment above each query first.
--
-- SQL ideas used in this file
--   JOIN                      connects two tables using a common column (Plant_ID or Record_ID)
--   GROUP BY + SUM/AVG/COUNT  makes one row for each group (for example each plant)
--   HAVING                    filters the groups after GROUP BY
--   CASE WHEN                 if-else inside SQL
--   CTE (WITH ... AS)         a named temporary result, so a long query can be read step by step
--   RANK() / DENSE_RANK()     window functions: give a rank number to each row
--   Views                     saved queries (see views.sql)
-- =====================================================================================

USE renewable_energy_analytics;

-- -------------------------------------------------------------------------------------
-- Q0. Check the key numbers: they must match Python, Power BI and Streamlit
-- -------------------------------------------------------------------------------------
SELECT  COUNT(*)                                        AS Records,                       -- 52,560
        ROUND(SUM(e.Energy_Generated_MWh), 0)           AS Total_Energy_MWh,              -- 9,805,015
        ROUND(SUM(e.Revenue) / 10000000, 1)             AS Revenue_INR_Crore,             -- 3,481.3
        ROUND(SUM(e.Operating_Cost) / 10000000, 1)      AS Operating_Cost_INR_Crore,      -- 531.5
        ROUND(SUM(m.Maintenance_Cost) / 10000000, 1)    AS Maintenance_Cost_INR_Crore,    -- 18.4
        ROUND(AVG(e.Efficiency_Percent), 2)             AS Avg_Efficiency_Pct,            -- 85.76
        ROUND(AVG(e.Capacity_Utilization), 2)           AS Avg_Capacity_Utilization_Pct   -- 28.68
FROM    Energy_Generation e
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID;

-- -------------------------------------------------------------------------------------
-- Q1. Which plants generate the highest amount of renewable energy?
-- -------------------------------------------------------------------------------------
SELECT  RANK() OVER (ORDER BY SUM(e.Energy_Generated_MWh) DESC) AS Rank_No,
        p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000, 1)            AS Total_GWh
FROM    Plants p
INNER JOIN Energy_Generation e ON e.Plant_ID = p.Plant_ID
GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Region
ORDER BY Rank_No
LIMIT 10;

-- -------------------------------------------------------------------------------------
-- Q2. Which energy type has the highest average generation?
--     Shown three ways: per 4-hour record, per plant, and per installed MW (fairest comparison).
-- -------------------------------------------------------------------------------------
WITH type_capacity AS (
    SELECT Energy_Type, COUNT(*) AS Plants, SUM(Installed_Capacity_MW) AS Installed_MW
    FROM   Plants
    GROUP BY Energy_Type
)
SELECT  p.Energy_Type,
        tc.Plants,
        tc.Installed_MW,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000, 1)               AS Total_GWh,
        ROUND(AVG(e.Energy_Generated_MWh), 2)                      AS Avg_MWh_per_Record,
        ROUND(MIN(e.Energy_Generated_MWh), 2)                      AS Min_MWh_per_Record,
        ROUND(MAX(e.Energy_Generated_MWh), 2)                      AS Max_MWh_per_Record,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000 / tc.Plants, 1)   AS Avg_GWh_per_Plant,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000 / tc.Installed_MW, 2) AS GWh_per_Installed_MW
FROM    Energy_Generation e
INNER JOIN Plants p          ON p.Plant_ID     = e.Plant_ID
INNER JOIN type_capacity tc  ON tc.Energy_Type = p.Energy_Type
GROUP BY p.Energy_Type, tc.Plants, tc.Installed_MW
ORDER BY GWh_per_Installed_MW DESC;

-- -------------------------------------------------------------------------------------
-- Q3. Which plants have the highest capacity utilization?
--     Utilization = energy / (installed MW x 4 hours x records) x 100
-- -------------------------------------------------------------------------------------
SELECT  DENSE_RANK() OVER (ORDER BY SUM(e.Energy_Generated_MWh) / (p.Installed_Capacity_MW * 4 * COUNT(*)) DESC) AS Rank_No,
        p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Installed_Capacity_MW,
        ROUND(SUM(e.Energy_Generated_MWh) / (p.Installed_Capacity_MW * 4 * COUNT(*)) * 100, 2) AS Capacity_Utilization_Pct
FROM    Plants p
INNER JOIN Energy_Generation e ON e.Plant_ID = p.Plant_ID
GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Installed_Capacity_MW
ORDER BY Rank_No
LIMIT 10;

-- -------------------------------------------------------------------------------------
-- Q4. Which regions generate the most energy?  (share of total uses a window over the grouped result)
-- -------------------------------------------------------------------------------------
SELECT  RANK() OVER (ORDER BY SUM(e.Energy_Generated_MWh) DESC)                   AS Rank_No,
        p.Region,
        COUNT(DISTINCT p.Plant_ID)                                                 AS Plants,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000, 1)                               AS Total_GWh,
        ROUND(SUM(e.Energy_Generated_MWh) / SUM(SUM(e.Energy_Generated_MWh)) OVER () * 100, 1) AS Share_of_Total_Pct
FROM    Plants p
INNER JOIN Energy_Generation e ON e.Plant_ID = p.Plant_ID
GROUP BY p.Region
ORDER BY Rank_No;

-- -------------------------------------------------------------------------------------
-- Q5. Which plants have the highest downtime?
--     LEFT JOIN from Plants keeps every plant even if it had no maintenance records;
--     HAVING keeps only plants that actually had downtime; CASE labels the severity.
-- -------------------------------------------------------------------------------------
SELECT  DENSE_RANK() OVER (ORDER BY SUM(m.Downtime_Hours) DESC) AS Rank_No,
        p.Plant_ID, p.Plant_Name, p.Energy_Type,
        SUM(m.Downtime_Hours)                                   AS Total_Downtime_Hours,
        ROUND(SUM(m.Downtime_Hours) / (4 * COUNT(e.Record_ID)) * 100, 2) AS Downtime_Rate_Pct,
        SUM(m.Plant_Status = 'Shutdown')                        AS Shutdown_Blocks,
        CASE WHEN SUM(m.Downtime_Hours) / (4 * COUNT(e.Record_ID)) * 100 >= 6 THEN 'High'
             WHEN SUM(m.Downtime_Hours) / (4 * COUNT(e.Record_ID)) * 100 >= 4 THEN 'Medium'
             ELSE 'Low' END                                     AS Downtime_Level
FROM    Plants p
LEFT JOIN Energy_Generation e   ON e.Plant_ID  = p.Plant_ID
LEFT JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type
HAVING  SUM(m.Downtime_Hours) > 0
ORDER BY Rank_No
LIMIT 10;

-- -------------------------------------------------------------------------------------
-- Q6. How does weather affect energy generation?
-- -------------------------------------------------------------------------------------
-- Q6a. Solar: utilization by irradiance band (daytime blocks only, start hours 8 and 12)
SELECT  CASE WHEN w.Solar_Irradiance < 200 THEN '1) under 200'
             WHEN w.Solar_Irradiance < 400 THEN '2) 200-400'
             WHEN w.Solar_Irradiance < 600 THEN '3) 400-600'
             WHEN w.Solar_Irradiance < 800 THEN '4) 600-800'
             ELSE '5) 800 and above' END           AS Irradiance_Band_Wm2,
        COUNT(*)                                   AS Records,
        ROUND(AVG(e.Capacity_Utilization), 2)      AS Avg_Utilization_Pct
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
WHERE   p.Energy_Type = 'Solar' AND e.Hour IN (8, 12)
GROUP BY Irradiance_Band_Wm2
ORDER BY Irradiance_Band_Wm2;

-- Q6b. Wind: utilization by wind-speed band
SELECT  CASE WHEN w.Wind_Speed_kmh < 10 THEN '1) under 10'
             WHEN w.Wind_Speed_kmh < 20 THEN '2) 10-20'
             WHEN w.Wind_Speed_kmh < 30 THEN '3) 20-30'
             WHEN w.Wind_Speed_kmh < 40 THEN '4) 30-40'
             WHEN w.Wind_Speed_kmh < 50 THEN '5) 40-50'
             ELSE '6) 50 and above' END            AS Wind_Speed_Band_kmh,
        COUNT(*)                                   AS Records,
        ROUND(AVG(e.Capacity_Utilization), 2)      AS Avg_Utilization_Pct
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
WHERE   p.Energy_Type = 'Wind'
GROUP BY Wind_Speed_Band_kmh
ORDER BY Wind_Speed_Band_kmh;

-- Q6c. Hydro: monthly rainfall (average per plant) against utilization
SELECT  MONTH(e.Date)                                         AS Month_No,
        MONTHNAME(e.Date)                                     AS Month_Name,
        ROUND(SUM(w.Rainfall_mm) / COUNT(DISTINCT e.Plant_ID), 1) AS Rainfall_mm_per_Plant,
        ROUND(AVG(e.Capacity_Utilization), 2)                 AS Avg_Utilization_Pct
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
WHERE   p.Energy_Type = 'Hydro'
GROUP BY MONTH(e.Date), MONTHNAME(e.Date)
ORDER BY Month_No;

-- Q6d. Correlation of each weather variable with utilization, per energy type
--      (Pearson r = (E[xy] - E[x]E[y]) / (sd_x * sd_y); MySQL has no CORR function)
SELECT  p.Energy_Type,
        ROUND((AVG(w.Solar_Irradiance * e.Capacity_Utilization) - AVG(w.Solar_Irradiance) * AVG(e.Capacity_Utilization))
              / (STDDEV_POP(w.Solar_Irradiance) * STDDEV_POP(e.Capacity_Utilization)), 2) AS r_Irradiance,
        ROUND((AVG(w.Wind_Speed_kmh * e.Capacity_Utilization) - AVG(w.Wind_Speed_kmh) * AVG(e.Capacity_Utilization))
              / (STDDEV_POP(w.Wind_Speed_kmh) * STDDEV_POP(e.Capacity_Utilization)), 2)   AS r_Wind_Speed,
        ROUND((AVG(w.Temperature_C * e.Capacity_Utilization) - AVG(w.Temperature_C) * AVG(e.Capacity_Utilization))
              / (STDDEV_POP(w.Temperature_C) * STDDEV_POP(e.Capacity_Utilization)), 2)    AS r_Temperature,
        ROUND((AVG(w.Rainfall_mm * e.Capacity_Utilization) - AVG(w.Rainfall_mm) * AVG(e.Capacity_Utilization))
              / (STDDEV_POP(w.Rainfall_mm) * STDDEV_POP(e.Capacity_Utilization)), 2)      AS r_Rainfall
FROM    Energy_Generation e
INNER JOIN Plants p       ON p.Plant_ID  = e.Plant_ID
INNER JOIN Weather_Data w ON w.Record_ID = e.Record_ID
GROUP BY p.Energy_Type;

-- -------------------------------------------------------------------------------------
-- Q7. Which plants have the lowest cost per MWh?  (operating + maintenance cost / energy)
-- -------------------------------------------------------------------------------------
SELECT  RANK() OVER (ORDER BY (SUM(e.Operating_Cost) + SUM(m.Maintenance_Cost)) / SUM(e.Energy_Generated_MWh)) AS Rank_No,
        p.Plant_ID, p.Plant_Name, p.Energy_Type,
        ROUND(SUM(e.Operating_Cost) / SUM(e.Energy_Generated_MWh), 2)   AS Operating_Cost_per_MWh,
        ROUND(SUM(m.Maintenance_Cost) / SUM(e.Energy_Generated_MWh), 2) AS Maintenance_Cost_per_MWh,
        ROUND((SUM(e.Operating_Cost) + SUM(m.Maintenance_Cost)) / SUM(e.Energy_Generated_MWh), 2) AS Cost_per_MWh
FROM    Plants p
INNER JOIN Energy_Generation e   ON e.Plant_ID  = p.Plant_ID
INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type
HAVING  SUM(e.Energy_Generated_MWh) > 0
ORDER BY Rank_No
LIMIT 10;

-- -------------------------------------------------------------------------------------
-- Q8. What are the top 10 plants by performance?
--     CTE pipeline: plant metrics -> scale 0-100 within energy type (window MIN/MAX) -> weighted score -> RANK.
--     Weights: 30% utilization, 25% efficiency, 20% availability, 15% cost (lower is better), 10% profit margin.
--     The same logic is stored as the view vw_plant_performance.
-- -------------------------------------------------------------------------------------
WITH plant_metrics AS (
    SELECT  p.Plant_ID, p.Plant_Name, p.Energy_Type,
            SUM(e.Energy_Generated_MWh) / (p.Installed_Capacity_MW * 4 * COUNT(*)) * 100          AS CU,
            AVG(e.Efficiency_Percent)                                                              AS Eff,
            AVG(e.Availability_Percent)                                                            AS Avail,
            (SUM(e.Operating_Cost) + SUM(m.Maintenance_Cost)) / SUM(e.Energy_Generated_MWh)        AS Cost_per_MWh,
            (SUM(e.Revenue) - SUM(e.Operating_Cost) - SUM(m.Maintenance_Cost)) / SUM(e.Revenue) * 100 AS Margin
    FROM    Plants p
    INNER JOIN Energy_Generation e   ON e.Plant_ID  = p.Plant_ID
    INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
    GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Installed_Capacity_MW
),
scaled AS (
    SELECT  pm.*,
            COALESCE((CU    - MIN(CU)    OVER w) / NULLIF(MAX(CU)    OVER w - MIN(CU)    OVER w, 0) * 100, 50) AS CU_Score,
            COALESCE((Eff   - MIN(Eff)   OVER w) / NULLIF(MAX(Eff)   OVER w - MIN(Eff)   OVER w, 0) * 100, 50) AS Eff_Score,
            COALESCE((Avail - MIN(Avail) OVER w) / NULLIF(MAX(Avail) OVER w - MIN(Avail) OVER w, 0) * 100, 50) AS Avail_Score,
            COALESCE(100 - (Cost_per_MWh - MIN(Cost_per_MWh) OVER w)
                           / NULLIF(MAX(Cost_per_MWh) OVER w - MIN(Cost_per_MWh) OVER w, 0) * 100, 50)         AS Cost_Score,
            COALESCE((Margin - MIN(Margin) OVER w) / NULLIF(MAX(Margin) OVER w - MIN(Margin) OVER w, 0) * 100, 50) AS Margin_Score
    FROM    plant_metrics pm
    WINDOW  w AS (PARTITION BY Energy_Type)
),
scored AS (
    SELECT  s.*,
            0.30 * CU_Score + 0.25 * Eff_Score + 0.20 * Avail_Score + 0.15 * Cost_Score + 0.10 * Margin_Score AS Performance_Score
    FROM    scaled s
)
SELECT  RANK() OVER (ORDER BY Performance_Score DESC)                          AS Rank_Overall,
        RANK() OVER (PARTITION BY Energy_Type ORDER BY Performance_Score DESC) AS Rank_in_Type,
        Plant_ID, Plant_Name, Energy_Type,
        ROUND(Performance_Score, 2) AS Performance_Score,
        ROUND(CU, 2) AS Utilization_Pct, ROUND(Eff, 2) AS Efficiency_Pct, ROUND(Avail, 2) AS Availability_Pct,
        ROUND(Cost_per_MWh, 0) AS Cost_per_MWh, ROUND(Margin, 1) AS Profit_Margin_Pct
FROM    scored
ORDER BY Rank_Overall, Plant_ID
LIMIT 10;

-- -------------------------------------------------------------------------------------
-- Q9. Which months have the highest energy generation?
-- -------------------------------------------------------------------------------------
-- Q9a. All plants together
SELECT  RANK() OVER (ORDER BY SUM(e.Energy_Generated_MWh) DESC) AS Rank_No,
        MONTH(e.Date)                                           AS Month_No,
        MONTHNAME(e.Date)                                       AS Month_Name,
        ROUND(SUM(e.Energy_Generated_MWh) / 1000, 1)            AS Total_GWh
FROM    Energy_Generation e
GROUP BY MONTH(e.Date), MONTHNAME(e.Date)
ORDER BY Rank_No;

-- Q9b. Best 3 months for each energy type (DENSE_RANK inside each type)
SELECT * FROM (
    SELECT  p.Energy_Type,
            DENSE_RANK() OVER (PARTITION BY p.Energy_Type ORDER BY SUM(e.Energy_Generated_MWh) DESC) AS Rank_in_Type,
            MONTHNAME(e.Date)                                AS Month_Name,
            ROUND(SUM(e.Energy_Generated_MWh) / 1000, 1)     AS Total_GWh
    FROM    Energy_Generation e
    INNER JOIN Plants p ON p.Plant_ID = e.Plant_ID
    GROUP BY p.Energy_Type, MONTH(e.Date), MONTHNAME(e.Date)
) ranked
WHERE Rank_in_Type <= 3
ORDER BY Energy_Type, Rank_in_Type;

-- -------------------------------------------------------------------------------------
-- Q10. Which plants have high capacity but relatively low generation?
--      High capacity = installed MW at or above the average plant.
--      Low generation = utilization below the average of the plant's own energy type.
--      Shortfall = MWh the plant would have produced at the type average.
-- -------------------------------------------------------------------------------------
WITH plant_cu AS (
    SELECT  p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Installed_Capacity_MW,
            SUM(e.Energy_Generated_MWh)                                                   AS Total_MWh,
            SUM(e.Energy_Generated_MWh) / (p.Installed_Capacity_MW * 4 * COUNT(*)) * 100 AS CU,
            p.Installed_Capacity_MW * 4 * COUNT(*)                                        AS Max_Possible_MWh
    FROM    Plants p
    INNER JOIN Energy_Generation e ON e.Plant_ID = p.Plant_ID
    GROUP BY p.Plant_ID, p.Plant_Name, p.Energy_Type, p.Installed_Capacity_MW
),
benchmarks AS (
    SELECT  pc.*,
            AVG(CU)                      OVER (PARTITION BY Energy_Type) AS Type_Avg_CU,
            AVG(Installed_Capacity_MW)   OVER ()                         AS Avg_Capacity_MW
    FROM    plant_cu pc
)
SELECT  Plant_ID, Plant_Name, Energy_Type, Installed_Capacity_MW,
        ROUND(CU, 2)          AS Utilization_Pct,
        ROUND(Type_Avg_CU, 2) AS Type_Avg_Utilization_Pct,
        ROUND((Type_Avg_CU - CU) / 100 * Max_Possible_MWh, 0) AS Shortfall_MWh,
        CASE WHEN Type_Avg_CU - CU >= 3 THEN 'Investigate'
             ELSE 'Slightly below peers' END                  AS Verdict
FROM    benchmarks
WHERE   Installed_Capacity_MW >= Avg_Capacity_MW
  AND   CU < Type_Avg_CU
ORDER BY Shortfall_MWh DESC;

-- -------------------------------------------------------------------------------------
-- Q11. Extra: plant status mix by energy type (CASE inside SUM = conditional count, in a CTE)
-- -------------------------------------------------------------------------------------
WITH status_counts AS (
    SELECT  p.Energy_Type,
            COUNT(*)                                                  AS Records,
            SUM(CASE WHEN m.Plant_Status = 'Operational'       THEN 1 ELSE 0 END) AS Operational,
            SUM(CASE WHEN m.Plant_Status = 'Partial Outage'    THEN 1 ELSE 0 END) AS Partial_Outage,
            SUM(CASE WHEN m.Plant_Status = 'Under Maintenance' THEN 1 ELSE 0 END) AS Under_Maintenance,
            SUM(CASE WHEN m.Plant_Status = 'Shutdown'          THEN 1 ELSE 0 END) AS Shutdown
    FROM    Energy_Generation e
    INNER JOIN Plants p              ON p.Plant_ID  = e.Plant_ID
    INNER JOIN Maintenance_Records m ON m.Record_ID = e.Record_ID
    GROUP BY p.Energy_Type
)
SELECT  Energy_Type, Records,
        ROUND(Operational       / Records * 100, 2) AS Operational_Pct,
        ROUND(Partial_Outage    / Records * 100, 2) AS Partial_Outage_Pct,
        ROUND(Under_Maintenance / Records * 100, 2) AS Under_Maintenance_Pct,
        ROUND(Shutdown          / Records * 100, 2) AS Shutdown_Pct
FROM    status_counts;

-- -------------------------------------------------------------------------------------
-- Q12. Views (run views.sql first) : quick checks that Power BI will see the same numbers
-- -------------------------------------------------------------------------------------
SELECT Rank_Overall, Plant_Name, Energy_Type, ROUND(Performance_Score, 2) AS Performance_Score, Performance_Class
FROM   vw_plant_performance
ORDER BY Rank_Overall, Plant_ID
LIMIT 10;

SELECT Energy_Type, ROUND(Total_Energy_MWh / 1000, 1) AS Total_GWh,
       ROUND(Capacity_Utilization_Rate, 2) AS Capacity_Utilization_Pct, ROUND(Profit_Margin_Pct, 1) AS Profit_Margin_Pct
FROM   vw_energy_type_summary;

SELECT Plant_Name, ROUND(Est_Energy_Lost_MWh, 0) AS Est_Energy_Lost_MWh, ROUND(Est_Revenue_Lost_INR_Crore, 2) AS Est_Revenue_Lost_INR_Crore
FROM   vw_downtime_summary
ORDER BY Est_Revenue_Lost_INR_Crore DESC
LIMIT 5;
