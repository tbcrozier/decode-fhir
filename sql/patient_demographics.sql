-- Patient Demographics Summary
-- Provides overview of patient population by demographics

SELECT
  gender,
  race,
  ethnicity,
  state,
  COUNT(*) as patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage,
  SUM(CASE WHEN deceased THEN 1 ELSE 0 END) as deceased_count,
  ROUND(AVG(DATE_DIFF(CURRENT_DATE(), birth_date, YEAR)), 1) as avg_age
FROM
  `fhir_analytics.patients`
GROUP BY
  gender, race, ethnicity, state
ORDER BY
  patient_count DESC;
