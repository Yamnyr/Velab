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
-- 2. STAGING AREA (Données brutes structurées)
--=========================================
-- Table pour stocker les données après parsing JSON
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
-- 3. CURATED AREA (Données propres & Historisées)
--=========================================
-- Dimension : Stations (SCD Type 1 ou 2)
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

-- Fait : Statut des stations (Historisation)
CREATE TABLE IF NOT EXISTS curated.fact_station_status (
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
-- 4. ANALYTICS AREA (Vues & Tables pour KPI)
--=========================================

-- Vue : Disponibilité globale actuelle
CREATE OR REPLACE VIEW analytics.vw_kpi_global_availability AS
SELECT 
    SUM(num_bikes_available) as total_bikes,
    SUM(mechanical_bikes) as total_mechanical,
    SUM(ebikes) as total_ebikes,
    SUM(num_docks_available) as total_empty_docks,
    MAX(status_timestamp) as last_update
FROM curated.fact_station_status
WHERE status_timestamp >= NOW() - INTERVAL '15 minutes';

-- Vue : Top Stations Critiques (Sous-capacité ou Pleines)
CREATE OR REPLACE VIEW analytics.vw_kpi_critical_stations AS
SELECT 
    d.station_name,
    d.arrondissement,
    f.num_bikes_available,
    f.num_docks_available,
    d.capacity,
    CASE 
        WHEN f.num_bikes_available = 0 THEN 'EMPTY'
        WHEN f.num_docks_available = 0 THEN 'FULL'
        ELSE 'NORMAL'
    END as station_state,
    f.status_timestamp
FROM curated.fact_station_status f
JOIN curated.dim_station d ON f.station_code = d.station_code
WHERE 
    f.status_timestamp = (SELECT MAX(status_timestamp) FROM curated.fact_station_status)
    AND (f.num_bikes_available = 0 OR f.num_docks_available = 0);

-- Vue : Taux de remplissage moyen par arrondissement
CREATE OR REPLACE VIEW analytics.vw_fill_rate_by_district AS
SELECT 
    d.arrondissement,
    AVG(f.num_bikes_available::FLOAT / NULLIF(d.capacity, 0)) * 100 as avg_fill_rate_pct,
    COUNT(DISTINCT d.station_code) as total_stations
FROM curated.fact_station_status f
JOIN curated.dim_station d ON f.station_code = d.station_code
WHERE f.status_timestamp = (SELECT MAX(status_timestamp) FROM curated.fact_station_status)
GROUP BY d.arrondissement
ORDER BY avg_fill_rate_pct DESC;
