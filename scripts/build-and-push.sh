#!/bin/bash
set -euo pipefail

# =============================================================================
# Build and Push Container Images to Artifact Registry
# =============================================================================

# Configuration
PROJECT_ID="${PROJECT_ID:-vocal-spirit-372618}"
REGION="${REGION:-us-central1}"
REPOSITORY="fhir-pipeline"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "=== FHIR Pipeline Container Build ==="
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Registry: ${REGISTRY}"
echo ""

# Authenticate Docker to Artifact Registry
echo "Authenticating Docker to Artifact Registry..."
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# Version tag (use timestamp for uniqueness)
VERSION="${VERSION:-$(date +%Y%m%d%H%M%S)}"
echo "Version tag: ${VERSION}"

# Build and push generate-synthea-fhir image
echo ""
echo "=== Building generate-synthea-fhir ==="
docker build \
    --platform linux/amd64 \
    -t "${REGISTRY}/generate-synthea-fhir:${VERSION}" \
    -t "${REGISTRY}/generate-synthea-fhir:latest" \
    -f "${ROOT_DIR}/cloud-run/generate-synthea-fhir/Dockerfile" \
    "${ROOT_DIR}/cloud-run/generate-synthea-fhir"

echo "Pushing generate-synthea-fhir..."
docker push "${REGISTRY}/generate-synthea-fhir:${VERSION}"
docker push "${REGISTRY}/generate-synthea-fhir:latest"

# Build and push parse-fhir-to-bq image
echo ""
echo "=== Building parse-fhir-to-bq ==="
docker build \
    --platform linux/amd64 \
    -t "${REGISTRY}/parse-fhir-to-bq:${VERSION}" \
    -t "${REGISTRY}/parse-fhir-to-bq:latest" \
    -f "${ROOT_DIR}/cloud-run/parse-fhir-to-bq/Dockerfile" \
    "${ROOT_DIR}"

echo "Pushing parse-fhir-to-bq..."
docker push "${REGISTRY}/parse-fhir-to-bq:${VERSION}"
docker push "${REGISTRY}/parse-fhir-to-bq:latest"

echo ""
echo "=== Build Complete ==="
echo "Images pushed to:"
echo "  - ${REGISTRY}/generate-synthea-fhir:latest"
echo "  - ${REGISTRY}/parse-fhir-to-bq:latest"
echo ""
echo "To execute the jobs:"
echo ""
echo "  # Generate 100 patients"
echo "  RUN_ID=\$(date +%Y%m%d_%H%M%S)_\$(openssl rand -hex 4)"
echo "  gcloud run jobs execute generate-synthea-fhir \\"
echo "      --region ${REGION} \\"
echo "      --set-env-vars=\"POPULATION=100,STATE=Tennessee,RUN_ID=\${RUN_ID}\""
echo ""
echo "  # Parse (after generate completes)"
echo "  gcloud run jobs execute parse-fhir-to-bq \\"
echo "      --region ${REGION} \\"
echo "      --set-env-vars=\"SOURCE_PREFIX=runs/\${RUN_ID}/fhir/\""
