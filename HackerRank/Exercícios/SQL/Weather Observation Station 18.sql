Select 
    ROUND(ABS(min(LAT_N) - max(LAT_N)) + ABS(min(LONG_W ) - max(LONG_W )),4)
FROM
    Station