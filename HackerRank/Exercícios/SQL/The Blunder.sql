WITH base AS (
    SELECT 
        *
        ,REGEXP_REPLACE(Salary, '0', '')  AS miscalculated
    FROM 
        EMPLOYEES 
)
    
SELECT 
    ROUND(AVG(Salary) - AVG(miscalculated)) + 1
FROM 
    base