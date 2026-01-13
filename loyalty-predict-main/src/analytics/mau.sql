WITH tb_dayli AS (
    SELECT DISTINCT
        date(substr(DtCriacao,0,11)) AS DtDia,
        IdCliente
    FROM
        transacoes
    ORDER BY 
        DtDia

),

tb_distinct_day AS (
    SELECT 
        DISTINCT DtDia AS dtRef
    FROM
        tb_dayli
)

SELECT 
    t1.dtRef,
    count( distinct IdCliente) as MAU,
    count( distinct t2.dtDia) as qtdeDias
FROM tb_distinct_day AS t1
LEFT JOIN tb_dayli AS t2
On t2.DtDia <= t1.dtRef
AND julianday(t1.dtRef) - julianday(t2.DtDia) < 28

GROUP BY t1.dtRef
ORDER BY t1.dtRef ASc
