DROP TABLE IF EXISTS standard.clientes;

CREATE TABLE standard.clientes AS
SELECT
    cod_cliente::integer                          AS cod_cliente,
    NULLIF(btrim(primeiro_nome), '')              AS primeiro_nome,
    NULLIF(btrim(ultimo_nome), '')                AS ultimo_nome,
    NULLIF(btrim(email), '')                      AS email,
    NULLIF(btrim(tipo_cliente), '')               AS tipo_cliente,
    NULLIF(btrim(data_inclusao), '')::timestamptz AS data_inclusao,
    NULLIF(btrim(cpfcnpj), '')                    AS cpfcnpj,
    NULLIF(btrim(data_nascimento), '')::date      AS data_nascimento,
    NULLIF(btrim(endereco), '')                   AS endereco,
    NULLIF(btrim(cep), '')                        AS cep,
    _sdc_extracted_at                             AS source_extracted_at,
    now()                                         AS processed_at
FROM raw.clientes;

ALTER TABLE standard.clientes ADD PRIMARY KEY (cod_cliente);
