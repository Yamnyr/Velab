/* 
=========================================================
  PROJET DATALAKEHOUSE VÉLIB - TP FIN DE SEMAINE
=========================================================
*/

--=========================================
-- 1. SCHEMAS
--=========================================
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS curated;
CREATE SCHEMA IF NOT EXISTS analytics;

--=========================================
-- 2. STAGING AREA
--=========================================
CREATE TABLE IF NOT EXISTS staging.velib_stations (
    stationcode VARCHAR(50),
    name VARCHAR(255),
    is_installed VARCHAR(10),
    capacity INT,
    numdocksavailable INT,
    numbikesavailable INT,
    mechanical INT,
    ebike INT,
    is_renting VARCHAR(10),
    is_returning VARCHAR(10),
    duedate TIMESTAMP,
    coordonnees_geo JSONB,
    nom_arrondissement_communes VARCHAR(255),
    ingestion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

--=========================================
-- 3. CURATED AREA
--=========================================
CREATE TABLE IF NOT EXISTS curated.dim_station (
    station_sk SERIAL PRIMARY KEY,
    station_code VARCHAR(50) UNIQUE,
    station_name VARCHAR(255),
    capacity INT,
    latitude FLOAT,
    longitude FLOAT,
    arrondissement VARCHAR(255),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS  curated.fact_station_status (
    status_id SERIAL PRIMARY KEY,
    station_code VARCHAR(50) REFERENCES curated.dim_station(station_code),
    is_installed BOOLEAN,
    is_renting BOOLEAN,
    is_returning BOOLEAN,
    num_docks_available INT,
    num_bikes_available INT,
    mechanical_bikes INT,
    ebikes INT,
    status_timestamp TIMESTAMP,
    ingestion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

--=========================================
-- 4. ANALYTICS AREA
--=========================================

-- Dernier statut par station (pour réutilisation)
CREATE OR REPLACE VIEW analytics.vw_latest_station_status AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER(PARTITION BY station_code ORDER BY status_timestamp DESC) AS rn
    FROM curated.fact_station_status
) t
WHERE rn = 1;

-- Disponibilité globale actuelle
CREATE OR REPLACE VIEW analytics.vw_kpi_global_availability AS
SELECT 
    SUM(COALESCE(num_bikes_available,0)) AS total_bikes,
    SUM(COALESCE(mechanical_bikes,0)) AS total_mechanical,
    SUM(COALESCE(ebikes,0)) AS total_ebikes,
    SUM(COALESCE(num_docks_available,0)) AS total_empty_docks,
    MAX(status_timestamp) AS last_update
FROM analytics.vw_latest_station_status;

-- Top Stations Critiques
CREATE OR REPLACE VIEW analytics.vw_kpi_critical_stations AS
SELECT 
    d.station_name,
    d.arrondissement,
    COALESCE(f.num_bikes_available,0) AS num_bikes_available,
    COALESCE(f.num_docks_available,0) AS num_docks_available,
    d.capacity,
    CASE 
        WHEN COALESCE(f.num_bikes_available,0) = 0 THEN 'EMPTY'
        WHEN COALESCE(f.num_docks_available,0) = 0 THEN 'FULL'
        ELSE 'NORMAL'
    END AS station_state,
    f.status_timestamp
FROM curated.dim_station d
LEFT JOIN analytics.vw_latest_station_status f
    ON f.station_code = d.station_code
WHERE COALESCE(f.num_bikes_available,0) = 0 
   OR COALESCE(f.num_docks_available,0) = 0;

-- Taux de remplissage moyen par arrondissement
CREATE OR REPLACE VIEW analytics.vw_fill_rate_by_district AS
SELECT 
    d.arrondissement,
    AVG(COALESCE(f.num_bikes_available,0)::FLOAT / NULLIF(d.capacity,0)) * 100 AS avg_fill_rate_pct,
    COUNT(DISTINCT d.station_code) AS total_stations
FROM curated.dim_station d
LEFT JOIN analytics.vw_latest_station_status f
    ON f.station_code = d.station_code
GROUP BY d.arrondissement
ORDER BY avg_fill_rate_pct DESC;

-- KPI : Taux de stations critiques
CREATE OR REPLACE VIEW analytics.vw_kpi_critical_rate AS
SELECT 
    ROUND(
        COUNT(*) FILTER (
            WHERE COALESCE(num_bikes_available,0) = 0 
               OR COALESCE(num_docks_available,0) = 0 
               OR COALESCE(num_bikes_available,0) < 5
        )::numeric 
        / COUNT(*) * 100, 2
    ) AS critical_station_pct,
    COUNT(*) FILTER (
        WHERE COALESCE(num_bikes_available,0) = 0 
           OR COALESCE(num_docks_available,0) = 0 
           OR COALESCE(num_bikes_available,0) < 5
    ) AS critical_stations,
    COUNT(*) AS total_stations,
    MAX(status_timestamp) AS last_update
FROM analytics.vw_latest_station_status;