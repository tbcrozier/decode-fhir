#!/bin/bash
set -euo pipefail

# =============================================================================
# Synthea FHIR Generator Entrypoint
# Generates synthetic patient data and uploads to GCS
# =============================================================================

# Required environment variables
: "${POPULATION:?POPULATION is required}"
: "${STATE:?STATE is required}"
: "${OUTPUT_BUCKET:?OUTPUT_BUCKET is required}"
: "${RUN_ID:?RUN_ID is required}"

# Optional environment variables
SEED="${SEED:-}"

echo "=== Synthea FHIR Generator ==="
echo "Population: ${POPULATION}"
echo "State: ${STATE}"
echo "Output: gs://${OUTPUT_BUCKET}/runs/${RUN_ID}/fhir/"
echo "Seed: ${SEED:-<random>}"
echo ""

# Create output directory
mkdir -p /app/output/fhir

# Build Synthea command (run JAR directly)
SYNTHEA_ARGS="-p ${POPULATION} ${STATE}"
SYNTHEA_ARGS="${SYNTHEA_ARGS} --exporter.fhir.export=true"
SYNTHEA_ARGS="${SYNTHEA_ARGS} --exporter.hospital.fhir.export=false"
SYNTHEA_ARGS="${SYNTHEA_ARGS} --exporter.practitioner.fhir.export=false"
SYNTHEA_ARGS="${SYNTHEA_ARGS} --exporter.baseDirectory=/app/output"

# Add seed if provided
if [[ -n "${SEED}" ]]; then
    SYNTHEA_ARGS="${SYNTHEA_ARGS} -s ${SEED}"
fi

# Run Synthea JAR directly
echo "Running Synthea..."
cd /app
java -jar synthea.jar ${SYNTHEA_ARGS}

# Count generated files
FHIR_COUNT=$(find /app/output/fhir -name "*.json" 2>/dev/null | wc -l)
echo "Generated ${FHIR_COUNT} FHIR bundles"

# Upload to GCS
echo "Uploading to gs://${OUTPUT_BUCKET}/runs/${RUN_ID}/fhir/..."
gsutil -m cp /app/output/fhir/*.json "gs://${OUTPUT_BUCKET}/runs/${RUN_ID}/fhir/"

echo "=== Upload Complete ==="
echo "Files uploaded to: gs://${OUTPUT_BUCKET}/runs/${RUN_ID}/fhir/"
