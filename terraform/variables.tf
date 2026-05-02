variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_number" {
  description = "GCP Project Number (for Cloud Build SA references)"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# -----------------------------------------------------------------------------
# Cloud Run Job Images
# Set these after building and pushing images, or leave empty for placeholder
# -----------------------------------------------------------------------------

variable "synthea_image" {
  description = "Container image for generate-synthea-fhir job (leave empty for placeholder)"
  type        = string
  default     = ""
}

variable "parser_image" {
  description = "Container image for parse-fhir-to-bq job (leave empty for placeholder)"
  type        = string
  default     = ""
}
