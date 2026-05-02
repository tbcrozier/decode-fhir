output "bigquery_dataset" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.fhir_analytics.dataset_id
}

output "processed_bucket" {
  description = "GCS bucket for processed data"
  value       = google_storage_bucket.processed.name
}

output "pipeline_service_account" {
  description = "Service account email for pipeline"
  value       = google_service_account.pipeline.email
}

# -----------------------------------------------------------------------------
# Cloud Run Outputs
# -----------------------------------------------------------------------------

output "artifact_registry_repository" {
  description = "Artifact Registry repository for container images"
  value       = google_artifact_registry_repository.fhir_pipeline.name
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for docker push"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.fhir_pipeline.repository_id}"
}

output "cloud_run_job_generate_synthea" {
  description = "Cloud Run job name for Synthea generation"
  value       = google_cloud_run_v2_job.generate_synthea_fhir.name
}

output "cloud_run_job_parse_fhir" {
  description = "Cloud Run job name for FHIR parsing"
  value       = google_cloud_run_v2_job.parse_fhir_to_bq.name
}
