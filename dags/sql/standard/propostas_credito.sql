drop table if exists standard.propostas_credito;

create table standard.propostas_credito as
select
    cod_proposta::integer as cod_proposta
    , cod_cliente::integer as cod_cliente
    , cod_colaborador::integer as cod_colaborador
    , nullif(btrim(data_entrada_proposta), '')::timestamptz as data_entrada_proposta
    , nullif(btrim(taxa_juros_mensal), '')::numeric as taxa_juros_mensal
    , nullif(btrim(valor_proposta), '')::numeric as valor_proposta
    , nullif(btrim(valor_financiamento), '')::numeric as valor_financiamento
    , nullif(btrim(valor_entrada), '')::numeric as valor_entrada
    , nullif(btrim(valor_prestacao), '')::numeric as valor_prestacao
    , nullif(btrim(quantidade_parcelas), '')::integer as quantidade_parcelas
    , nullif(btrim(carencia), '')::integer as carencia
    , nullif(btrim(status_proposta), '') as status_proposta
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.propostas_credito;

alter table standard.propostas_credito add primary key (cod_proposta);
