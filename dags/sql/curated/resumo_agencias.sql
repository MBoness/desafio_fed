-- standard -> curated: one row per branch with its customer base and account movement.
-- Example analyst-ready table (see DECISIONS.md, D12): the real curated rules would come
-- from the business. Rebuilt on every run; Airflow runs it in a single transaction.
-- Accounts and transactions are aggregated separately before the join, so counts and
-- sums are not multiplied by the one-to-many joins.
DROP TABLE IF EXISTS curated.resumo_agencias;

CREATE TABLE curated.resumo_agencias AS
WITH contas_por_agencia AS (
    SELECT
        cod_agencia,
        count(DISTINCT cod_cliente) AS qtd_clientes,
        count(*)                    AS qtd_contas,
        sum(saldo_total)            AS saldo_total
    FROM standard.contas
    GROUP BY cod_agencia
),

transacoes_por_agencia AS (
    -- Sign convention of the source: positive = money in, negative = money out.
    SELECT
        c.cod_agencia,
        count(*)                                                    AS qtd_transacoes,
        coalesce(sum(t.valor_transacao) FILTER (WHERE t.valor_transacao > 0), 0)  AS valor_entradas,
        coalesce(-sum(t.valor_transacao) FILTER (WHERE t.valor_transacao < 0), 0) AS valor_saidas
    FROM standard.transacoes AS t
    JOIN standard.contas AS c USING (num_conta)
    GROUP BY c.cod_agencia
)

SELECT
    a.cod_agencia,
    a.nome,
    a.cidade,
    a.uf,
    a.tipo_agencia,
    coalesce(ca.qtd_clientes, 0)             AS qtd_clientes,
    coalesce(ca.qtd_contas, 0)               AS qtd_contas,
    -- Money rounded to cents: the source values carry floating-point residue.
    round(coalesce(ca.saldo_total, 0), 2)    AS saldo_total,
    coalesce(ta.qtd_transacoes, 0)           AS qtd_transacoes,
    round(coalesce(ta.valor_entradas, 0), 2) AS valor_entradas,
    round(coalesce(ta.valor_saidas, 0), 2)   AS valor_saidas,
    now()                                    AS processed_at
FROM standard.agencias AS a
LEFT JOIN contas_por_agencia AS ca USING (cod_agencia)
LEFT JOIN transacoes_por_agencia AS ta USING (cod_agencia);

ALTER TABLE curated.resumo_agencias ADD PRIMARY KEY (cod_agencia);
