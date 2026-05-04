# FHIR Clinical Data Pipeline

A production-style data pipeline that ingests FHIR R4 bundles from Synthea, transforms them into analytics-ready tables, and loads them into BigQuery for clinical analysis.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GCP Infrastructure                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐ │
│  │  Cloud Run Job   │    │   GCS Bucket    │    │       BigQuery          │ │
│  │  generate-       │───▶│                 │    │    fhir_analytics       │ │
│  │  synthea-fhir    │    │ synthea-fhir-   │    │                         │ │
│  │                  │    │ decode/runs/    │    │  - patients             │ │
│  │  Synthea v3.3.0  │    │                 │    │  - conditions           │ │
│  └──────────────────┘    └────────┬────────┘    │  - observations         │ │
│                                   │             │  - pipeline_runs        │ │
│                                   ▼             │  - qc_summary           │ │
│                          ┌─────────────────┐    │                         │ │
│                          │  Cloud Run Job  │───▶│                         │ │
│                          │  parse-fhir-    │    └─────────────────────────┘ │
│                          │  to-bq          │                                │
│                          │                 │                                │
│                          │  Python Parser  │                                │
│                          └─────────────────┘                                │
│                                                                              │
│  Images stored in Artifact Registry: fhir-pipeline                          │
│  Infrastructure managed by Terraform                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
.
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # GCS, BigQuery, IAM resources
│   ├── cloud_run.tf       # Artifact Registry, Cloud Run Jobs
│   ├── variables.tf       # Configuration variables
│   ├── outputs.tf         # Resource references
│   └── terraform.tfvars
├── cloud-run/              # Container definitions
│   ├── generate-synthea-fhir/
│   │   ├── Dockerfile     # Multi-stage: JDK build, JRE runtime
│   │   └── entrypoint.sh  # Run Synthea JAR, upload to GCS
│   └── parse-fhir-to-bq/
│       ├── Dockerfile     # Python 3.11-slim
│       └── entrypoint.sh  # Run pipeline with env vars
├── scripts/
│   └── build-and-push.sh  # Build containers, push to Artifact Registry
├── pipeline/               # Python data pipeline
│   ├── main.py            # Pipeline entry point
│   ├── fhir_parser.py     # FHIR R4 resource parsing
│   ├── bigquery_loader.py # BigQuery load operations
│   └── requirements.txt
├── sql/                    # Analytics queries
│   ├── patient_demographics.sql
│   ├── condition_prevalence.sql
│   ├── vital_signs_summary.sql
│   ├── lab_results_abnormal.sql
│   └── patient_risk_cohort.sql
└── README.md
```

## Data Model

The pipeline transforms nested FHIR bundles into a normalized star schema:

| Table | Description | Key Fields |
|-------|-------------|------------|
| `patients` | Patient demographics | patient_id, birth_date, gender, race, ethnicity, location |
| `conditions` | Clinical conditions (diagnoses) | condition_id, patient_id, SNOMED code, clinical_status, onset/abatement dates |
| `observations` | Vital signs and lab results | observation_id, patient_id, LOINC code, category, value, effective_date |

## Setup

### Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated
- Terraform >= 1.0
- Python >= 3.10

### 1. Deploy Infrastructure

```bash
cd terraform

# Create your tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID

# Deploy
terraform init
terraform plan
terraform apply
```

### 2. Build and Push Container Images

```bash
# Build containers for linux/amd64 and push to Artifact Registry
./scripts/build-and-push.sh
```

### 3. Run the Pipeline (Cloud Run)

The pipeline consists of two Cloud Run Jobs that run sequentially:

```bash
# Generate synthetic FHIR data (100 patients)
RUN_ID=$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)
gcloud run jobs execute generate-synthea-fhir \
    --region us-central1 \
    --update-env-vars="POPULATION=100,STATE=Tennessee,RUN_ID=${RUN_ID}"

# After generate completes, parse and load to BigQuery
gcloud run jobs execute parse-fhir-to-bq \
    --region us-central1 \
    --update-env-vars="SOURCE_PREFIX=runs/${RUN_ID}/fhir/"
```

| Job | Purpose | Resources | Timeout |
|-----|---------|-----------|---------|
| `generate-synthea-fhir` | Generate FHIR bundles with Synthea, upload to GCS | 2 CPU, 4Gi | 1 hour |
| `parse-fhir-to-bq` | Parse FHIR from GCS, load to BigQuery, write QC metrics | 2 CPU, 2Gi | 30 min |

### 4. Run the Pipeline (Local)

```bash
cd pipeline

# Install dependencies
pip install -r requirements.txt

# Run against Cloud Run generated data
python main.py --project-id YOUR_PROJECT_ID --source-prefix "runs/${RUN_ID}/fhir/"

# Or test with a subset
python main.py --project-id YOUR_PROJECT_ID --max-files 100
```

### 5. Query the Data

Run the analytics queries in BigQuery console or via `bq` CLI:

```bash
bq query --use_legacy_sql=false < sql/condition_prevalence.sql
```

## Analytics Examples

### Condition Prevalence
Identify top conditions in the patient population with demographic breakdown.

### Patient Risk Cohort
Build patient cohorts based on:
- Multiple chronic conditions
- Age thresholds
- Recent vital signs

### Abnormal Lab Detection
Statistical outlier detection for lab values (z-score > 2).

## Design Decisions

1. **Containerized Jobs**: Cloud Run Jobs provide serverless execution with automatic scaling and no infrastructure management. Multi-stage Docker builds minimize image size.

2. **Run Tracking**: Each pipeline execution generates a unique `run_id` for data lineage. All records include `run_id` and `loaded_at` for traceability and rollback capability.

3. **QC Metrics**: Automatic quality control summary written to `qc_summary` table with success rates, record counts, and processing performance.

4. **Batch Processing**: Processes files in configurable batches to balance memory usage and throughput.

5. **Parallel Downloads**: Uses ThreadPoolExecutor for concurrent GCS downloads.

6. **Append-Only Loading**: Default write disposition is WRITE_APPEND, suitable for incremental loads.

7. **Schema-on-Write**: BigQuery schemas defined in Terraform ensure type safety and documentation.

8. **FHIR R4 Compatibility**: Parser handles US Core extensions (race, ethnicity) and various value types.

