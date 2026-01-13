with base as (
select 
     count(*),
    CONCAT('There are a total of ', count(*),' ',lower(OCCUPATION),'s.') as text
from 
    OCCUPATIONS 
group by 
    OCCUPATION
    order by 1
)
, base2 as (
    select 
   CONCAT(NAME,'(',SUBSTRING(OCCUPATION,1,1),')') as text
from 
    OCCUPATIONS
order by 1
)

select 
    text
from
    base2
union
select 
    text 
from 
    base
order by 1