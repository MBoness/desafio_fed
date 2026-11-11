DROP TABLE IF EXISTS standard.colaboradores;

CREATE TABLE standard.colaboradores AS
SELECT
    cod_colaborador::integer                     AS cod_colaborador,
    NULLIF(btrim(primeiro_nome), '')             AS primeiro_nome,
    NULLIF(btrim(ultimo_nome), '')               AS ultimo_nome,
    NULLIF(btrim(email), '')                     AS email,
    NULLIF(btrim(cpf), '')                       AS cpf,
    NULLIF(btrim(data_nascimento), '')::date     AS data_nascimento,
    NULLIF(btrim(endereco), '')                  AS endereco,
    NULLIF(btrim(cep), '')                       AS cep,
    _sdc_extracted_at                            AS source_extracted_at,
    now()                                        AS processed_at
FROM raw.colaboradores;

ALTER TABLE standard.colaboradores ADD PRIMARY KEY (cod_colaborador);
