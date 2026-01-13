SELECT 
    substr(DtCriacao,0,11) as DtDia,
    count(DISTINCT IdCliente) as DAU
 FROM transacoes
 GROUP By 1 order by 1 