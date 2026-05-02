# =============================================================================
# Cloud Run Jobs for FHIR Pipeline
# =============================================================================

# -----------------------------------------------------------------------------
# Artifact Registry - Container Image Storage
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "fhir_pipeline" {
  location      = var.region
  repository_id = "fhir-pipeline"
  description   = "Container images for FHIR data pipeline"
  format        = "DOCKER"

  labels = {
    environment = "demo"
  }
}

# -----------------------------------------------------------------------------
# Cloud Run Job: Generate Synthea FHIR Data
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "generate_synthea_fhir" {
  name     = "generate-synthea-fhir"
  location = var.region

  template {
    template {
      containers {
        # Use placeholder image for initial deploy, update after building real image
        image = var.synthea_image != "" ? var.synthea_image : "us-docker.pkg.dev/cloudrun/container/hello"

        resources {
          limits = {
            cpu    = "2"
            memory = "4Gi"
          }
        }

        # Default environment variables (can be overridden at execution time)
        env {
          name  = "OUTPUT_BUCKET"
          value = "synthea-fhir-decode"
        }
      }

      timeout     = "3600s" # 1 hour
      max_retries = 0

      service_account = google_service_account.pipeline.email
    }
  }

  labels = {
    environment = "demo"
    component   = "data-generator"
  }

  depends_on = [
    google_artifact_registry_repository.fhir_pipeline
  ]
}

# -----------------------------------------------------------------------------
# Cloud Run Job: Parse FHIR to BigQuery
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "parse_fhir_to_bq" {
  name     = "parse-fhir-to-bq"
  location = var.region

  template {
    template {
      containers {
        # Use placeholder image for initial deploy, update after building real image
        image = var.parser_image != "" ? var.parser_image : "us-docker.pkg.dev/cloudrun/container/hello"

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }

        # Default environment variables
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "SOURCE_BUCKET"
          value = "synthea-fhir-decode"
        }
      }

      timeout     = "1800s" # 30 minutes
      max_retries = 0

      service_account = google_service_account.pipeline.email
    }
  }

  labels = {
    environment = "demo"
    component   = "data-parser"
  }

  depends_on = [
    google_artifact_registry_repository.fhir_pipeline
  ]
}

# -----------------------------------------------------------------------------
# IAM: Grant Cloud Run Invoker to Pipeline Service Account
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_job_iam_member" "generate_synthea_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.generate_synthea_fhir.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_cloud_run_v2_job_iam_member" "parse_fhir_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.parse_fhir_to_bq.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pipeline.email}"
}
