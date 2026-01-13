WITH tb_daily AS (
    SELECT 
        DISTINCT
        IdCliente,
        SUBSTR(DtCriacao,0,11) AS dtdia
    FROM 
        transacoes 
),

tb_idade AS (
select 
    IdCliente
    ,cast(max(julianday('now') - julianday(dtdia)) as INT) AS qtdeDiasPrimTransacao 
    ,cast(min(julianday('now') - julianday(dtdia)) as INT) AS qtdeDiasUltmTransacao 
from tb_daily
GROUP BY idCliente
),

tb_rn AS (  
SELECT
    *,
    row_number() OVER (PARTITION BY idCliente ORDER BY dtdia DESC) as rndia
FROM 
    tb_daily
),

tb_penultima_ativacao as (
select 
    *, cast(julianday('now') - julianday(dtdia) as int) as qtdeDiasPenultimaTransacao
from
     tb_rn 
where rndia = 2
)

select 
    t1.*,
    t2.qtdeDiasPenultimaTransacao,
    CASE 
        WHEN qtdeDiasPrimTransacao <= 7 THEN '01-CURIOSO'
        WHEN qtdeDiasUltTransacao <=7 AND qtdeDiasPenultimaTransacao - qtdeDiasUltTransacao <= 14 THEN '02-FIEL'
    END as teste
 from tb_idade as t1
 left join tb_penultima_ativacao as t2
 on t1.idCliente = t2.idCliente