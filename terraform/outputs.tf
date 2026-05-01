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
