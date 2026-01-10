WITH base AS (
    SELECT 
        MAX(LAT_N) AS LAT_N 
    FROM    
        STATION
    WHERE
        LAT_N < 137.2345 
)

SELECT 
    ROUND(LONG_W,4)
FROM 
    station join base ON base.LAT_N = STATION.lAT_N