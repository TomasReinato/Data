WITH base AS (
    SELECT 
        MIN(LAT_N) AS LAT_N 
    FROM    
        STATION
    WHERE
        LAT_N > 38.7780 
)

SELECT 
    ROUND(LONG_W,4)
FROM 
    station join base ON base.LAT_N = STATION.lAT_N