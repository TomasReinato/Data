SELECT 
  CASE 
    WHEN A + B <= C THEN 'Not A Triangle'
    WHEN A = B  AND B = C THEN 'Equilateral' 
    WHEN A = B  OR B = C OR A = C THEN 'Isosceles'
    WHEN A <> B  AND B <> C AND A <> C THEN 'Scalene'
    ELSE NULL 
  END AS teste 
FROM 
    triangles