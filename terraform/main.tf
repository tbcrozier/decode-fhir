# FHIR Clinical Data Pipeline - GCP Infrastructure
# Demonstrates: IaC, GCP, data engineering infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Cloud Storage - Data Lake Layers
# -----------------------------------------------------------------------------

# Raw layer - source FHIR bundles (already exists: gs://synthea-fhir-decode/raw/)
# We reference the existing bucket, not create it

# Processed layer - flattened, parsed FHIR resources
resource "google_storage_bucket" "processed" {
  name          = "${var.project_id}-fhir-processed"
  location      = var.region
  force_destroy = true # For demo purposes only

  uniform_bucket_level_access = true

  labels = {
    environment = "demo"
    data_layer  = "processed"
  }
}

# -----------------------------------------------------------------------------
# BigQuery - Analytics Data Warehouse
# -----------------------------------------------------------------------------

resource "google_bigquery_dataset" "fhir_analytics" {
  dataset_id    = "fhir_analytics"
  friendly_name = "FHIR Clinical Analytics"
  description   = "Analytics-ready clinical data derived from FHIR bundles"
  location      = var.region

  labels = {
    environment = "demo"
  }
}

# Patient dimension table
resource "google_bigquery_table" "patients" {
  dataset_id          = google_bigquery_dataset.fhir_analytics.dataset_id
  table_id            = "patients"
  deletion_protection = false

  schema = jsonencode([
    { name = "patient_id", type = "STRING", mode = "REQUIRED", description = "FHIR Patient resource ID" },
    { name = "birth_date", type = "DATE", mode = "NULLABLE", description = "Patient date of birth" },
    { name = "gender", type = "STRING", mode = "NULLABLE", description = "Patient gender" },
    { name = "race", type = "STRING", mode = "NULLABLE", description = "Patient race (US Core extension)" },
    { name = "ethnicity", type = "STRING", mode = "NULLABLE", description = "Patient ethnicity (US Core extension)" },
    { name = "city", type = "STRING", mode = "NULLABLE", description = "Patient city" },
    { name = "state", type = "STRING", mode = "NULLABLE", description = "Patient state" },
    { name = "postal_code", type = "STRING", mode = "NULLABLE", description = "Patient postal code" },
    { name = "deceased", type = "BOOLEAN", mode = "NULLABLE", description = "Whether patient is deceased" },
    { name = "deceased_date", type = "DATE", mode = "NULLABLE", description = "Date of death if applicable" },
    { name = "run_id", type = "STRING", mode = "REQUIRED", description = "Pipeline run identifier for lineage" },
    { name = "loaded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Pipeline load timestamp" }
  ])
}

# Conditions fact table
resource "google_bigquery_table" "conditions" {
  dataset_id          = google_bigquery_dataset.fhir_analytics.dataset_id
  table_id            = "conditions"
  deletion_protection = false

  schema = jsonencode([
    { name = "condition_id", type = "STRING", mode = "REQUIRED", description = "FHIR Condition resource ID" },
    { name = "patient_id", type = "STRING", mode = "REQUIRED", description = "Reference to patient" },
    { name = "code", type = "STRING", mode = "NULLABLE", description = "SNOMED CT code" },
    { name = "code_display", type = "STRING", mode = "NULLABLE", description = "Human readable condition name" },
    { name = "clinical_status", type = "STRING", mode = "NULLABLE", description = "active, resolved, etc." },
    { name = "onset_date", type = "DATE", mode = "NULLABLE", description = "When condition started" },
    { name = "abatement_date", type = "DATE", mode = "NULLABLE", description = "When condition ended" },
    { name = "run_id", type = "STRING", mode = "REQUIRED", description = "Pipeline run identifier for lineage" },
    { name = "loaded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Pipeline load timestamp" }
  ])
}

# Observations fact table (vital signs, lab results)
resource "google_bigquery_table" "observations" {
  dataset_id          = google_bigquery_dataset.fhir_analytics.dataset_id
  table_id            = "observations"
  deletion_protection = false

  schema = jsonencode([
    { name = "observation_id", type = "STRING", mode = "REQUIRED", description = "FHIR Observation resource ID" },
    { name = "patient_id", type = "STRING", mode = "REQUIRED", description = "Reference to patient" },
    { name = "code", type = "STRING", mode = "NULLABLE", description = "LOINC code" },
    { name = "code_display", type = "STRING", mode = "NULLABLE", description = "Human readable observation name" },
    { name = "category", type = "STRING", mode = "NULLABLE", description = "vital-signs, laboratory, etc." },
    { name = "value_quantity", type = "FLOAT64", mode = "NULLABLE", description = "Numeric value" },
    { name = "value_unit", type = "STRING", mode = "NULLABLE", description = "Unit of measure" },
    { name = "value_string", type = "STRING", mode = "NULLABLE", description = "String value if not numeric" },
    { name = "effective_date", type = "TIMESTAMP", mode = "NULLABLE", description = "When observation was made" },
    { name = "run_id", type = "STRING", mode = "REQUIRED", description = "Pipeline run identifier for lineage" },
    { name = "loaded_at", type = "TIMESTAMP", mode = "REQUIRED", description = "Pipeline load timestamp" }
  ])
}

# Pipeline runs metadata table - tracks each execution for reproducibility
resource "google_bigquery_table" "pipeline_runs" {
  dataset_id          = google_bigquery_dataset.fhir_analytics.dataset_id
  table_id            = "pipeline_runs"
  deletion_protection = false

  schema = jsonencode([
    { name = "run_id", type = "STRING", mode = "REQUIRED", description = "Unique identifier for this pipeline run" },
    { name = "started_at", type = "TIMESTAMP", mode = "REQUIRED", description = "When the pipeline started" },
    { name = "completed_at", type = "TIMESTAMP", mode = "NULLABLE", description = "When the pipeline finished" },
    { name = "status", type = "STRING", mode = "REQUIRED", description = "running, success, failed" },
    { name = "source_bucket", type = "STRING", mode = "NULLABLE", description = "Source GCS bucket" },
    { name = "source_prefix", type = "STRING", mode = "NULLABLE", description = "Source path prefix" },
    { name = "files_processed", type = "INT64", mode = "NULLABLE", description = "Number of FHIR bundles processed" },
    { name = "patients_loaded", type = "INT64", mode = "NULLABLE", description = "Rows loaded to patients table" },
    { name = "conditions_loaded", type = "INT64", mode = "NULLABLE", description = "Rows loaded to conditions table" },
    { name = "observations_loaded", type = "INT64", mode = "NULLABLE", description = "Rows loaded to observations table" },
    { name = "error_message", type = "STRING", mode = "NULLABLE", description = "Error details if failed" },
    { name = "parameters", type = "JSON", mode = "NULLABLE", description = "Full pipeline parameters for reproducibility" }
  ])
}

# QC summary table - quality control metrics for each pipeline run
resource "google_bigquery_table" "qc_summary" {
  dataset_id          = google_bigquery_dataset.fhir_analytics.dataset_id
  table_id            = "qc_summary"
  deletion_protection = false

  schema = jsonencode([
    { name = "run_id", type = "STRING", mode = "REQUIRED", description = "Pipeline run identifier" },
    { name = "created_at", type = "TIMESTAMP", mode = "REQUIRED", description = "When this QC summary was created" },
    { name = "files_processed", type = "INT64", mode = "NULLABLE", description = "Number of files successfully processed" },
    { name = "files_failed", type = "INT64", mode = "NULLABLE", description = "Number of files that failed processing" },
    { name = "success_rate", type = "FLOAT64", mode = "NULLABLE", description = "Percentage of files processed successfully" },
    { name = "patients_count", type = "INT64", mode = "NULLABLE", description = "Total patient records loaded" },
    { name = "conditions_count", type = "INT64", mode = "NULLABLE", description = "Total condition records loaded" },
    { name = "observations_count", type = "INT64", mode = "NULLABLE", description = "Total observation records loaded" },
    { name = "conditions_per_patient", type = "FLOAT64", mode = "NULLABLE", description = "Average conditions per patient" },
    { name = "observations_per_patient", type = "FLOAT64", mode = "NULLABLE", description = "Average observations per patient" },
    { name = "observation_date_min", type = "STRING", mode = "NULLABLE", description = "Earliest observation date in dataset" },
    { name = "observation_date_max", type = "STRING", mode = "NULLABLE", description = "Latest observation date in dataset" },
    { name = "processing_duration_seconds", type = "FLOAT64", mode = "NULLABLE", description = "Total pipeline processing time" },
    { name = "records_per_second", type = "FLOAT64", mode = "NULLABLE", description = "Processing throughput" }
  ])
}

# -----------------------------------------------------------------------------
# Service Account for Pipeline
# -----------------------------------------------------------------------------

resource "google_service_account" "pipeline" {
  account_id   = "fhir-pipeline"
  display_name = "FHIR Pipeline Service Account"
  description  = "Service account for running the FHIR data pipeline"
}

# Grant access to read/write to source bucket (read raw data, write generated data)
resource "google_storage_bucket_iam_member" "pipeline_source_admin" {
  bucket = "synthea-fhir-decode"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# Grant access to write to processed bucket
resource "google_storage_bucket_iam_member" "pipeline_processed_write" {
  bucket = google_storage_bucket.processed.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# Grant access to BigQuery
resource "google_bigquery_dataset_iam_member" "pipeline_bq_write" {
  dataset_id = google_bigquery_dataset.fhir_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_project_iam_member" "pipeline_bq_job" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}
