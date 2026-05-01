-- Condition Prevalence Analysis
-- Top conditions by patient count with demographic breakdown

WITH patient_conditions AS (
  SELECT DISTINCT
    c.patient_id,
    c.code,
    c.code_display,
    p.gender,
    p.race,
    DATE_DIFF(CURRENT_DATE(), p.birth_date, YEAR) as age
  FROM
    `fhir_analytics.conditions` c
  JOIN
    `fhir_analytics.patients` p ON c.patient_id = p.patient_id
  WHERE
    c.clinical_status = 'active'
)
SELECT
  code,
  code_display as condition_name,
  COUNT(DISTINCT patient_id) as patient_count,
  ROUND(COUNT(DISTINCT patient_id) * 100.0 / (SELECT COUNT(*) FROM `fhir_analytics.patients`), 2) as prevalence_pct,
  ROUND(AVG(age), 1) as avg_patient_age,
  COUNTIF(gender = 'male') as male_count,
  COUNTIF(gender = 'female') as female_count
FROM
  patient_conditions
GROUP BY
  code, code_display
HAVING
  COUNT(DISTINCT patient_id) >= 10
ORDER BY
  patient_count DESC
LIMIT 25;
