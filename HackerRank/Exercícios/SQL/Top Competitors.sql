SELECT 
    hackers.hacker_id
    ,hackers.name
FROM  submissions
LEFT JOIN hackers  ON submissions.hacker_id = hackers.hacker_id
LEFT JOIN challenges ON challenges.challenge_id = submissions.challenge_id 
LEFT JOIN difficulty ON difficulty.difficulty_level = challenges.difficulty_level
WHERE 
    submissions.score = difficulty.score 
GROUP BY  
    1,2
HAVING 
    count(DISTINCT submissions.submission_id)>1
ORDER BY 
    count(DISTINCT submissions.submission_id) DESC,1
