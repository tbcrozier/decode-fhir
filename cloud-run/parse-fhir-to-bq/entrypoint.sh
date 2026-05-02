#!/bin/bash
set -euo pipefail

# =============================================================================
# FHIR to BigQuery Parser Entrypoint
# Parses FHIR bundles from GCS and loads to BigQuery
# =============================================================================

echo "=== FHIR to BigQuery Parser ==="
echo "Project ID: ${PROJECT_ID:-<not set>}"
echo "Source Bucket: ${SOURCE_BUCKET:-synthea-fhir-decode}"
echo "Source Prefix: ${SOURCE_PREFIX:-raw/synthea_tennessee_500/}"
echo "Max Files: ${MAX_FILES:-<all>}"
echo "Batch Size: ${BATCH_SIZE:-100}"
echo ""

# Run the pipeline
# Environment variables are read by main.py via argparse defaults
python /app/main.py

echo "=== Pipeline Complete ==="
