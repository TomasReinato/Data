SELECT
    salary * months AS earnings,
    count(*)
FROM
    employee 
GROUP BY earnings
ORDER BY 2 DESC
LIMIT 1