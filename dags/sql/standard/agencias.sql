-- raw -> standard: typed columns, blanks as NULL, no Meltano (_sdc_*) columns.
-- Rebuilt on every run; Airflow runs all statements in a single transaction.
drop table if exists standard.agencias;

create table standard.agencias as
select
    cod_agencia::integer as cod_agencia
    , nullif(btrim(nome), '') as nome
    , nullif(btrim(endereco), '') as endereco
    , nullif(btrim(cidade), '') as cidade
    , nullif(btrim(uf), '') as uf
    , nullif(btrim(data_abertura), '')::date as data_abertura
    , nullif(btrim(tipo_agencia), '') as tipo_agencia
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.agencias;

alter table standard.agencias add primary key (cod_agencia);
