DROP TABLE IF EXISTS standard.colaborador_agencia;

CREATE TABLE standard.colaborador_agencia AS
SELECT
    cod_colaborador::integer AS cod_colaborador,
    cod_agencia::integer     AS cod_agencia,
    _sdc_extracted_at        AS source_extracted_at,
    now()                    AS processed_at
FROM raw.colaborador_agencia;

ALTER TABLE standard.colaborador_agencia ADD PRIMARY KEY (cod_colaborador);
