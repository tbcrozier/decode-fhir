# Multi-stage build for Synthea FHIR Generator
# Generates synthetic patient data and uploads to GCS

# =============================================================================
# Stage 1: Build Synthea
# =============================================================================
FROM --platform=linux/amd64 eclipse-temurin:17-jdk AS builder

WORKDIR /build

# Install git
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Clone Synthea v3.3.0
RUN git clone --depth 1 --branch v3.3.0 https://github.com/synthetichealth/synthea.git

WORKDIR /build/synthea

# Build Synthea (skip tests for faster build)
RUN ./gradlew build -x test

# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM --platform=linux/amd64 eclipse-temurin:17-jre

WORKDIR /app

# Install Google Cloud SDK for gsutil
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Copy only the built JAR and required resources (not the full source)
COPY --from=builder /build/synthea/build/libs/synthea-with-dependencies.jar /app/synthea.jar
COPY --from=builder /build/synthea/src/main/resources /app/resources

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
