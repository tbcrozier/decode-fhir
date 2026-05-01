-- Abnormal Lab Results Detection
-- Identifies potentially abnormal lab values using statistical thresholds
-- Note: In production, this would use clinical reference ranges

WITH lab_stats AS (
  SELECT
    code,
    code_display,
    value_unit,
    AVG(value_quantity) as mean_val,
    STDDEV(value_quantity) as std_val,
    COUNT(*) as total_obs
  FROM
    `fhir_analytics.observations`
  WHERE
    category = 'laboratory'
    AND value_quantity IS NOT NULL
  GROUP BY
    code, code_display, value_unit
  HAVING
    COUNT(*) >= 50
)
SELECT
  o.patient_id,
  o.code,
  o.code_display as lab_test,
  o.value_quantity as value,
  o.value_unit as unit,
  o.effective_date,
  ROUND(s.mean_val, 2) as population_mean,
  ROUND((o.value_quantity - s.mean_val) / s.std_val, 2) as z_score,
  CASE
    WHEN (o.value_quantity - s.mean_val) / s.std_val > 2 THEN 'HIGH'
    WHEN (o.value_quantity - s.mean_val) / s.std_val < -2 THEN 'LOW'
    ELSE 'NORMAL'
  END as flag
FROM
  `fhir_analytics.observations` o
JOIN
  lab_stats s ON o.code = s.code
WHERE
  o.category = 'laboratory'
  AND o.value_quantity IS NOT NULL
  AND ABS((o.value_quantity - s.mean_val) / s.std_val) > 2
ORDER BY
  ABS((o.value_quantity - s.mean_val) / s.std_val) DESC
LIMIT 100;
