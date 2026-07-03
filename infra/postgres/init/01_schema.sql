-- AtmoFrance - Schema relationnel Gold + referentiel geographique
-- Active l'extension geospatiale
CREATE EXTENSION IF NOT EXISTS postgis;

-- Referentiel des regions administratives (contours geographiques)
CREATE TABLE IF NOT EXISTS region (
    code_region    VARCHAR(3) PRIMARY KEY,
    nom            VARCHAR(120) NOT NULL,
    geom           GEOMETRY(MultiPolygon, 4326)
);

-- Referentiel des stations de mesure
CREATE TABLE IF NOT EXISTS station (
    code_station   VARCHAR(20) PRIMARY KEY,
    nom            VARCHAR(200) NOT NULL,
    code_region    VARCHAR(3) REFERENCES region(code_region),
    type_station   VARCHAR(40),          -- urbaine, periurbaine, rurale, trafic, industrielle
    type_influence VARCHAR(40),          -- fond, trafic, industrielle
    latitude       DOUBLE PRECISION,
    longitude      DOUBLE PRECISION,
    geom           GEOMETRY(Point, 4326)
);

CREATE INDEX IF NOT EXISTS idx_station_geom ON station USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_station_region ON station (code_region);

-- Table des polluants (dimension)
CREATE TABLE IF NOT EXISTS polluant (
    code_polluant  VARCHAR(10) PRIMARY KEY, -- NO2, O3, PM10, PM25, SO2, CO
    libelle        VARCHAR(80) NOT NULL,
    unite          VARCHAR(20) NOT NULL,    -- ug/m3, mg/m3
    seuil_info     DOUBLE PRECISION,        -- seuil d'information
    seuil_alerte   DOUBLE PRECISION         -- seuil d'alerte
);

-- Table de faits : mesures agregees Gold (moyenne horaire par station/polluant)
CREATE TABLE IF NOT EXISTS mesure_horaire (
    id             BIGSERIAL PRIMARY KEY,
    code_station   VARCHAR(20) REFERENCES station(code_station),
    code_polluant  VARCHAR(10) REFERENCES polluant(code_polluant),
    horodatage     TIMESTAMPTZ NOT NULL,
    valeur         DOUBLE PRECISION,
    validite       SMALLINT,                -- 1 = valide, 0 = invalide
    depassement    VARCHAR(10),             -- null, info, alerte
    UNIQUE (code_station, code_polluant, horodatage)
);

CREATE INDEX IF NOT EXISTS idx_mesure_horodatage ON mesure_horaire (horodatage);
CREATE INDEX IF NOT EXISTS idx_mesure_station_pol ON mesure_horaire (code_station, code_polluant);

-- Table d'agregat journalier (datamart pour l'API et le dashboard)
CREATE TABLE IF NOT EXISTS indice_journalier (
    id             BIGSERIAL PRIMARY KEY,
    code_station   VARCHAR(20) REFERENCES station(code_station),
    jour           DATE NOT NULL,
    indice_atmo    SMALLINT,                -- 1 (bon) a 6 (extremement mauvais)
    qualificatif   VARCHAR(40),
    polluant_resp  VARCHAR(10),             -- polluant responsable de l'indice
    UNIQUE (code_station, jour)
);

CREATE INDEX IF NOT EXISTS idx_indice_jour ON indice_journalier (jour);

-- Donnees de reference des polluants (seuils reglementaires FR/UE)
INSERT INTO polluant (code_polluant, libelle, unite, seuil_info, seuil_alerte) VALUES
    ('NO2',  'Dioxyde d''azote',        'ug/m3', 200, 400),
    ('O3',   'Ozone',                    'ug/m3', 180, 240),
    ('PM10', 'Particules < 10um',        'ug/m3', 50,  80),
    ('PM25', 'Particules fines < 2.5um', 'ug/m3', NULL, NULL),
    ('SO2',  'Dioxyde de soufre',        'ug/m3', 300, 500),
    ('CO',   'Monoxyde de carbone',      'mg/m3', NULL, NULL)
ON CONFLICT (code_polluant) DO NOTHING;
