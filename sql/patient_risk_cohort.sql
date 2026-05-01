-- Patient Risk Cohort Builder
-- Identifies high-risk patients based on multiple chronic conditions
-- Demonstrates cohort building for clinical analytics

WITH chronic_conditions AS (
  SELECT
    c.patient_id,
    COUNT(DISTINCT c.code) as condition_count,
    ARRAY_AGG(DISTINCT c.code_display LIMIT 10) as conditions
  FROM
    `fhir_analytics.conditions` c
  WHERE
    c.clinical_status = 'active'
  GROUP BY
    c.patient_id
),
recent_vitals AS (
  SELECT
    patient_id,
    MAX(CASE WHEN code = '8310-5' THEN value_quantity END) as last_temp_c,
    MAX(CASE WHEN code = '8867-4' THEN value_quantity END) as last_heart_rate,
    MAX(CASE WHEN code = '8480-6' THEN value_quantity END) as last_systolic_bp,
    MAX(effective_date) as last_vital_date
  FROM
    `fhir_analytics.observations`
  WHERE
    category = 'vital-signs'
    AND effective_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
  GROUP BY
    patient_id
)
SELECT
  p.patient_id,
  p.gender,
  DATE_DIFF(CURRENT_DATE(), p.birth_date, YEAR) as age,
  p.city,
  p.state,
  cc.condition_count,
  cc.conditions,
  rv.last_systolic_bp,
  rv.last_heart_rate,
  rv.last_vital_date,
  CASE
    WHEN cc.condition_count >= 5 AND DATE_DIFF(CURRENT_DATE(), p.birth_date, YEAR) >= 65 THEN 'HIGH'
    WHEN cc.condition_count >= 3 THEN 'MEDIUM'
    ELSE 'LOW'
  END as risk_tier
FROM
  `fhir_analytics.patients` p
LEFT JOIN
  chronic_conditions cc ON p.patient_id = cc.patient_id
LEFT JOIN
  recent_vitals rv ON p.patient_id = rv.patient_id
WHERE
  p.deceased IS NOT TRUE
ORDER BY
  cc.condition_count DESC NULLS LAST,
  DATE_DIFF(CURRENT_DATE(), p.birth_date, YEAR) DESC
LIMIT 100;
