# FHIR Clinical Data Pipeline

A production-style data pipeline that ingests FHIR R4 bundles from Synthea, transforms them into analytics-ready tables, and loads them into BigQuery for clinical analysis.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GCP Infrastructure                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐  │
│   │   GCS Bucket    │     │  Python Pipeline │     │    BigQuery     │  │
│   │   (Raw Layer)   │────▶│                 │────▶│  fhir_analytics │  │
│   │                 │     │  - Parse FHIR   │     │                 │  │
│   │ synthea-fhir-   │     │  - Flatten JSON │     │  - patients     │  │
│   │ decode/raw/     │     │  - Validate     │     │  - conditions   │  │
│   │                 │     │  - Batch load   │     │  - observations │  │
│   └─────────────────┘     └─────────────────┘     └─────────────────┘  │
│                                                                         │
│   Infrastructure managed by Terraform                                   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
.
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # GCS, BigQuery, IAM resources
│   ├── variables.tf       # Configuration variables
│   ├── outputs.tf         # Resource references
│   └── terraform.tfvars.example
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

### 2. Run the Pipeline

```bash
cd pipeline

# Install dependencies
pip install -r requirements.txt

# Run pipeline (process all 5000 patient bundles)
python main.py --project-id YOUR_PROJECT_ID

# Or test with a subset
python main.py --project-id YOUR_PROJECT_ID --max-files 100
```

### 3. Query the Data

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

1. **Batch Processing**: Processes files in configurable batches to balance memory usage and throughput.

2. **Parallel Downloads**: Uses ThreadPoolExecutor for concurrent GCS downloads.

3. **Append-Only Loading**: Default write disposition is WRITE_APPEND, suitable for incremental loads.

4. **Schema-on-Write**: BigQuery schemas defined in Terraform ensure type safety and documentation.

5. **FHIR R4 Compatibility**: Parser handles US Core extensions (race, ethnicity) and various value types.

## Future Enhancements

- [ ] Add data quality checks (Great Expectations)
- [ ] Implement Airflow DAG for scheduling
- [ ] Add unit tests for FHIR parsing
- [ ] Create Looker Studio dashboard
- [ ] Add Cloud Monitoring alerts
