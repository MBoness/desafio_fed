drop table if exists standard.colaborador_agencia;

create table standard.colaborador_agencia as
select
    cod_colaborador::integer as cod_colaborador
    , cod_agencia::integer as cod_agencia
    , _sdc_extracted_at as source_extracted_at
    , now() as processed_at
from raw.colaborador_agencia;

alter table standard.colaborador_agencia add primary key (cod_colaborador);
