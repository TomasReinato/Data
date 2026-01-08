WITH base AS (
    SELECT 
        ID
        ,NAME 
        , right(name,3) as ENDING
    FROM
        STUDENTS 
    WHERE 
        MARKS > 75
    )
    
SELECT 
     NAME 
FROM 
    base 
ORDER BY  
    ENDING, 
    ID