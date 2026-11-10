DROP TABLE IF EXISTS standard.contas;

CREATE TABLE standard.contas AS
SELECT
    num_conta::integer                                      AS num_conta,
    cod_cliente::integer                                    AS cod_cliente,
    cod_agencia::integer                                    AS cod_agencia,
    cod_colaborador::integer                                AS cod_colaborador,
    NULLIF(btrim(tipo_conta), '')                           AS tipo_conta,
    NULLIF(btrim(data_abertura), '')::timestamptz           AS data_abertura,
    NULLIF(btrim(saldo_total), '')::numeric                 AS saldo_total,
    NULLIF(btrim(saldo_disponivel), '')::numeric            AS saldo_disponivel,
    NULLIF(btrim(data_ultimo_lancamento), '')::timestamptz  AS data_ultimo_lancamento,
    _sdc_extracted_at                                       AS source_extracted_at,
    now()                                                   AS processed_at
FROM raw.contas;

ALTER TABLE standard.contas ADD PRIMARY KEY (num_conta);
