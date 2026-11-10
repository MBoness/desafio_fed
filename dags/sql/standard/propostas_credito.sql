DROP TABLE IF EXISTS standard.propostas_credito;

CREATE TABLE standard.propostas_credito AS
SELECT
    cod_proposta::integer                                  AS cod_proposta,
    cod_cliente::integer                                   AS cod_cliente,
    cod_colaborador::integer                               AS cod_colaborador,
    NULLIF(btrim(data_entrada_proposta), '')::timestamptz  AS data_entrada_proposta,
    NULLIF(btrim(taxa_juros_mensal), '')::numeric          AS taxa_juros_mensal,
    NULLIF(btrim(valor_proposta), '')::numeric             AS valor_proposta,
    NULLIF(btrim(valor_financiamento), '')::numeric        AS valor_financiamento,
    NULLIF(btrim(valor_entrada), '')::numeric              AS valor_entrada,
    NULLIF(btrim(valor_prestacao), '')::numeric            AS valor_prestacao,
    NULLIF(btrim(quantidade_parcelas), '')::integer        AS quantidade_parcelas,
    NULLIF(btrim(carencia), '')::integer                   AS carencia,
    NULLIF(btrim(status_proposta), '')                     AS status_proposta,
    _sdc_extracted_at                                      AS source_extracted_at,
    now()                                                  AS processed_at
FROM raw.propostas_credito;

ALTER TABLE standard.propostas_credito ADD PRIMARY KEY (cod_proposta);
