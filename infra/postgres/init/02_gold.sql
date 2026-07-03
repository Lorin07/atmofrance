-- AtmoFrance - Tables Gold chargees par Spark pour l'API et le dashboard.
CREATE TABLE IF NOT EXISTS gold_indice_journalier (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    jour           DATE,
    indice_atmo    SMALLINT,
    qualificatif   VARCHAR(40),
    polluant_resp  VARCHAR(10),
    latitude       DOUBLE PRECISION,
    longitude      DOUBLE PRECISION,
    geom           GEOMETRY(Point, 4326),
    UNIQUE (code_site, jour)
);
CREATE INDEX IF NOT EXISTS idx_gold_indice_jour ON gold_indice_journalier (jour);
CREATE INDEX IF NOT EXISTS idx_gold_indice_geom ON gold_indice_journalier USING GIST (geom);

CREATE TABLE IF NOT EXISTS gold_moyennes_journalieres (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    code_polluant  VARCHAR(10),
    jour           DATE,
    moyenne        DOUBLE PRECISION,
    minimum        DOUBLE PRECISION,
    maximum        DOUBLE PRECISION,
    nb_mesures     INTEGER,
    unite          VARCHAR(20),
    UNIQUE (code_site, code_polluant, jour)
);
CREATE INDEX IF NOT EXISTS idx_gold_moy_jour ON gold_moyennes_journalieres (jour);
CREATE INDEX IF NOT EXISTS idx_gold_moy_pol ON gold_moyennes_journalieres (code_polluant);

CREATE TABLE IF NOT EXISTS gold_depassements (
    id             BIGSERIAL PRIMARY KEY,
    code_site      VARCHAR(20),
    nom_site       VARCHAR(200),
    code_polluant  VARCHAR(10),
    horodatage     TIMESTAMPTZ,
    jour           DATE,
    valeur         DOUBLE PRECISION,
    unite          VARCHAR(20),
    depassement    VARCHAR(10)
);
CREATE INDEX IF NOT EXISTS idx_gold_dep_jour ON gold_depassements (jour);
CREATE INDEX IF NOT EXISTS idx_gold_dep_niveau ON gold_depassements (depassement);
