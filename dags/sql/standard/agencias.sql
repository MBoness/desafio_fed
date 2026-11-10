-- raw -> standard: typed columns, blanks as NULL, no Meltano (_sdc_*) columns.
-- Rebuilt on every run; Airflow runs both statements in a single transaction.
DROP TABLE IF EXISTS standard.agencias;

CREATE TABLE standard.agencias AS
SELECT
    cod_agencia::integer                       AS cod_agencia,
    NULLIF(btrim(nome), '')                    AS nome,
    NULLIF(btrim(endereco), '')                AS endereco,
    NULLIF(btrim(cidade), '')                  AS cidade,
    NULLIF(btrim(uf), '')                      AS uf,
    NULLIF(btrim(data_abertura), '')::date     AS data_abertura,
    NULLIF(btrim(tipo_agencia), '')            AS tipo_agencia,
    _sdc_extracted_at                          AS source_extracted_at,
    now()                                      AS processed_at
FROM raw.agencias;

ALTER TABLE standard.agencias ADD PRIMARY KEY (cod_agencia);
