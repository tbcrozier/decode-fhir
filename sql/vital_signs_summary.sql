-- Vital Signs Summary
-- Statistical summary of key vital signs observations

SELECT
  code,
  code_display as vital_sign,
  value_unit as unit,
  COUNT(*) as observation_count,
  COUNT(DISTINCT patient_id) as patient_count,
  ROUND(AVG(value_quantity), 2) as avg_value,
  ROUND(STDDEV(value_quantity), 2) as std_dev,
  ROUND(MIN(value_quantity), 2) as min_value,
  ROUND(APPROX_QUANTILES(value_quantity, 4)[OFFSET(2)], 2) as median_value,
  ROUND(MAX(value_quantity), 2) as max_value
FROM
  `fhir_analytics.observations`
WHERE
  category = 'vital-signs'
  AND value_quantity IS NOT NULL
GROUP BY
  code, code_display, value_unit
ORDER BY
  observation_count DESC;
