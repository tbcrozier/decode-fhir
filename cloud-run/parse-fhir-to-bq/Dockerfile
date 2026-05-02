# FHIR to BigQuery Parser Container
# Parses FHIR bundles from GCS and loads to BigQuery

FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for layer caching
COPY pipeline/requirements.txt /app/requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy pipeline code
COPY pipeline/ /app/

# Copy entrypoint script
COPY cloud-run/parse-fhir-to-bq/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
