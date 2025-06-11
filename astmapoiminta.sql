/* Astmapoiminta mukaan kroonisten sairauksien skriptiin 

Aikaisemmin todetut diagnoosit: 
- Potilaalla on J45-diagnoosi ja se on diagnosoitu tai tunnistettu työterveydessä 
viimeisen 3 vuoden aikana (kaikki alaluokat, pää- ja sivudiagnoosit)
- Ei lääkärin tai hoitajan vastaanottoa diagnoosiin liittyen viimeisen vuoden ajalta 
(kaikki lääkärin vastaanottolajit)

TAI Uudet / todetut diagnoosit:
- Potilaalla on tunnistettu ensimmäistä kertaa diagnoosi viimeisen vuoden aikana, 
mutta ei kontrolli käyntiä viimeisen 6kk aikana.

Koskee molempia hakusääntöjä:

Potilaalla on tällä hetkellä voimassa oleva työterveyssopimus, 
joka ei kiellä pitkäaikaissairauksien hoitoa.
 
*/

/* Haetaan diagnoosipäivät */

SELECT
  person_id, person_ssn,
  CASE
	WHEN dg LIKE '%J45%' THEN 'J45'
  END AS dg,
  substring(dbo.udf_convertclariondatetime(max(dg_date_clarion), 0), 1, 10) as dg_date,
  case when min(dg_date_clarion) < dbo.udf_getclarionday(getdate()-365) then 1
  else 0 end as diagnosed_3years_to_1year_ago,
  company_id
  into #tmpDIAGNOOSIT
FROM (

  SELECT
    rekist.ptr AS person_id,
    rekist.ht AS person_ssn,
    sairaus.tns AS dg,
    sairaus.pvm AS dg_date_clarion,
    rekist.ynro AS company_id
  FROM
    sairaus
    JOIN rekist ON rekist.ht=sairaus.ht  
  WHERE
    (tns LIKE '%J45%')
    AND isnull(sala, '')<>'K'
    AND sairaus.pvm between dbo.udf_GetClarionDay(getdate()-1095) and dbo.udf_GetClarionDay(getdate()) --diagnoosi 3v sisällä
    AND rekist.ynro>0

  UNION

  SELECT
    rekist.ptr AS person_id,
    rekist.ht AS person_ssn,
    sairaus.tns1 AS dg,
    pvm AS dg_date_clarion,
    rekist.ynro AS company_id
  FROM
    sairaus

    JOIN rekist ON rekist.ht=sairaus.ht
  WHERE
    (tns1 LIKE '%J45%')
    AND isnull(sala, '')<>'K'
    AND pvm between dbo.udf_GetClarionDay(getdate()-1095) and dbo.udf_GetClarionDay(getdate())
    AND rekist.ynro>0

  UNION

  SELECT
    rekist.ptr AS person_id,
    rekist.ht AS person_ssn,
    kertomusdiagnoosit.dg_koodi AS dg,
    toteamispvm AS dg_date_clarion,
    rekist.ynro AS company_id
  FROM 
    kertomusdiagnoosit
    JOIN rekist ON rekist.ht=kertomusdiagnoosit.ht    
  WHERE
    (dg_koodi LIKE '%J45%')
    AND toteamispvm between dbo.udf_GetClarionDay(getdate()-1095) and dbo.udf_GetClarionDay(getdate())
    AND rekist.ynro>0

  UNION

  SELECT
    rekist.ptr AS person_id,
    rekist.ht AS person_ssn,
    atodist.t1 AS dg1,
    p0x1 AS dg_date_clarion,
    rekist.ynro as company_id
  FROM 
    atodist
    JOIN rekist ON rekist.ht=atodist.ht    
  WHERE
    (t1 LIKE '%J45%')
    AND isnull(sala, '')<>'K'
    AND p0x1 between dbo.udf_GetClarionDay(getdate()-1095) and dbo.udf_GetClarionDay(getdate())
    AND rekist.ynro>0

  ) AS all_diagnoses

  -- person has not been added to SHI3 worklist during last year
  LEFT JOIN aika ON aika.ht=all_diagnoses.person_ssn
    AND aika.lkri='SHI3'
    AND aika.pvm between dbo.udf_getclarionday(getdate()-365) AND dbo.udf_getclarionday(getdate())

  -- filter out Premium customers
  LEFT JOIN pkonseptit ON pkonseptit.ht=all_diagnoses.person_ssn
     AND pkonseptit.konseptin_tunnus in ('PREMIUM', 'PREMIUMV')
     AND pkonseptit.voimassa_apvm<=dbo.udf_getclarionday(getdate())
     AND (pkonseptit.voimassa_lpvm=0 OR pkonseptit.voimassa_lpvm>dbo.udf_getclarionday(getdate()))

WHERE
  aika.ht IS NULL
  and pkonseptit.ht IS NULL

GROUP BY
  person_id, person_ssn,
  CASE
	WHEN dg LIKE '%J45%' THEN 'J45'
  END,
  company_id

--HAVING
--  -- Skip people whose last diagnosis is within last 180 days
--  max(dg_date_clarion)<dbo.udf_getclarionday(getdate()-180)

ORDER BY
  person_id


select HT, DATEDIFF(DAY, '1800-12-28',GetDate())-max(PVM_XXX) as pv_viimeisesta_seurannasta 
into #TMP_viimeisinkaynti
FROM [Doctorex].[dbo].kertomusdiagnoosit
where (DG_KOODI LIKE '%J45%') OR (ICPC_KOODI LIKE '%R96%') --lääkärin tai hoitajan diagnoosikoodi
group by HT

select  d.*,v.* from #tmpDIAGNOOSIT d left join #TMP_viimeisinkaynti v on d.person_ssn=v.HT
where diagnosed_3years_to_1year_ago=0



select d.*,v.*,
case when (d.diagnosed_3years_to_1year_ago=0 and v.pv_viimeisesta_seurannasta > 180) then 1 
when  d.diagnosed_3years_to_1year_ago=0 and v.pv_viimeisesta_seurannasta <= 180 then 0 
when d.diagnosed_3years_to_1year_ago=1 and v.pv_viimeisesta_seurannasta > 365 then 1 
else 0 end as otetaanmukaan
into #tmp_kokonaan
from #tmpDIAGNOOSIT d
left join #TMP_viimeisinkaynti v on d.person_ssn=v.HT

select HT, dg, dg_date, diagnosed_3years_to_1year_ago, company_id,pv_viimeisesta_seurannasta 
from #tmp_kokonaan where otetaanmukaan=1
