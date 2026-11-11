drop table if exists standard.colaboradores;

create table standard.colaboradores as
select
    cod_colaborador::integer as cod_colaborador
    , nullif(btrim(primeiro_nome), '') as primeiro_nome
    , nullif(btrim(ultimo_nome), '') as ultimo_nome
    , nullif(btrim(email), '') as email
    , nullif(btrim(cpf), '') as cpf
    , nullif(btrim(data_nascimento), '')::date as data_nascimento
    , nullif(btrim(endereco), '') as endereco
    , nullif(btrim(cep), '') as cep
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.colaboradores;

alter table standard.colaboradores add primary key (cod_colaborador);
