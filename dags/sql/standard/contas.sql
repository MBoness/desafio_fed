drop table if exists standard.contas;

create table standard.contas as
select
    num_conta::integer as num_conta
    , cod_cliente::integer as cod_cliente
    , cod_agencia::integer as cod_agencia
    , cod_colaborador::integer as cod_colaborador
    , nullif(btrim(tipo_conta), '') as tipo_conta
    , nullif(btrim(data_abertura), '')::timestamptz as data_abertura
    , nullif(btrim(saldo_total), '')::numeric as saldo_total
    , nullif(btrim(saldo_disponivel), '')::numeric as saldo_disponivel
    , nullif(btrim(data_ultimo_lancamento), '')::timestamptz as data_ultimo_lancamento
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.contas;

alter table standard.contas add primary key (num_conta);
