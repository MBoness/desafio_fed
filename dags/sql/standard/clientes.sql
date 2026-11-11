drop table if exists standard.clientes;

create table standard.clientes as
select
    cod_cliente::integer as cod_cliente
    , nullif(btrim(primeiro_nome), '') as primeiro_nome
    , nullif(btrim(ultimo_nome), '') as ultimo_nome
    , nullif(btrim(email), '') as email
    , nullif(btrim(tipo_cliente), '') as tipo_cliente
    , nullif(btrim(data_inclusao), '')::timestamptz as data_inclusao
    , nullif(btrim(cpfcnpj), '') as cpfcnpj
    , nullif(btrim(data_nascimento), '')::date as data_nascimento
    , nullif(btrim(endereco), '') as endereco
    , nullif(btrim(cep), '') as cep
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.clientes;

alter table standard.clientes add primary key (cod_cliente);
