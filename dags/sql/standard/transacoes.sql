DROP TABLE IF EXISTS standard.transacoes;

CREATE TABLE standard.transacoes AS
SELECT
    cod_transacao::integer                           AS cod_transacao,
    num_conta::integer                               AS num_conta,
    NULLIF(btrim(data_transacao), '')::timestamptz   AS data_transacao,
    NULLIF(btrim(nome_transacao), '')                AS nome_transacao,
    NULLIF(btrim(valor_transacao), '')::numeric      AS valor_transacao,
    _sdc_extracted_at                                AS source_extracted_at,
    now()                                            AS processed_at
FROM raw.transacoes;

ALTER TABLE standard.transacoes ADD PRIMARY KEY (cod_transacao);
