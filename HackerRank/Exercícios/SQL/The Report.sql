SELECT 
    CASE WHEN grade >= 8 THEN Name ELSE NULL end AS Name
    ,grade
    ,marks 
FROM  Students  
JOIN grades ON students.marks >= min_mark and students.marks <= max_mark
ORDER BY grade DESC, name, marks