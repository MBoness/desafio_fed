-- standard -> curated: one row per branch with its customer base and account movement.
-- Example analyst-ready table (see DECISIONS.md, D12): the real curated rules would come
-- from the business. Rebuilt on every run; Airflow runs it in a single transaction.
-- Accounts and transactions are aggregated separately before the join, so counts and
-- sums are not multiplied by the one-to-many joins.
drop table if exists curated.resumo_agencias;

create table curated.resumo_agencias as
with
    contas_por_agencia as (
        select
            cod_agencia
            , count(distinct cod_cliente) as qtd_clientes
            , count(*) as qtd_contas
            , sum(saldo_total) as saldo_total
        from standard.contas
        group by cod_agencia
    )

    , transacoes_por_agencia as (
        -- Sign convention of the source: positive = money in, negative = money out.
        select
            c.cod_agencia
            , count(*) as qtd_transacoes
            , sum(t.valor_transacao) filter (where t.valor_transacao > 0) as valor_entradas
            , -sum(t.valor_transacao) filter (where t.valor_transacao < 0) as valor_saidas
        from standard.transacoes as t
        inner join standard.contas as c
            on t.num_conta = c.num_conta
        group by c.cod_agencia
    )

select
    a.cod_agencia
    , a.nome
    , a.cidade
    , a.uf
    , a.tipo_agencia
    , coalesce(ca.qtd_clientes, 0) as qtd_clientes
    , coalesce(ca.qtd_contas, 0) as qtd_contas
    -- Money rounded to cents: the source values carry floating-point residue.
    , round(coalesce(ca.saldo_total, 0), 2) as saldo_total
    , coalesce(ta.qtd_transacoes, 0) as qtd_transacoes
    , round(coalesce(ta.valor_entradas, 0), 2) as valor_entradas
    , round(coalesce(ta.valor_saidas, 0), 2) as valor_saidas
    , now() as processed_at
from standard.agencias as a
left join contas_por_agencia as ca
    on a.cod_agencia = ca.cod_agencia
left join transacoes_por_agencia as ta
    on a.cod_agencia = ta.cod_agencia;

alter table curated.resumo_agencias add primary key (cod_agencia);
