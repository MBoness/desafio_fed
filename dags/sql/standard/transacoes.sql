drop table if exists standard.transacoes;

create table standard.transacoes as
select
    cod_transacao::integer as cod_transacao
    , num_conta::integer as num_conta
    , nullif(btrim(data_transacao), '')::timestamptz as data_transacao
    , nullif(btrim(nome_transacao), '') as nome_transacao
    , nullif(btrim(valor_transacao), '')::numeric as valor_transacao
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.transacoes;

alter table standard.transacoes add primary key (cod_transacao);
