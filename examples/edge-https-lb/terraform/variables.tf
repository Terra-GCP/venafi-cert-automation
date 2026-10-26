variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Region for Cloud Run, Artifact Registry, and Cloud Build"
  default     = "us-central1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for example app, LB, AR, and Cloud Build trigger"
  default     = "venafi-cert-edge"
}

variable "secret_cert_name" {
  type        = string
  description = "Secret Manager secret ID holding the PEM certificate"
}

variable "secret_key_name" {
  type        = string
  description = "Secret Manager secret ID holding the PEM private key"
}

variable "status_app_image" {
  type        = string
  description = "Optional status app image URI override"
  default     = ""
}

variable "tf_state_bucket" {
  type        = string
  description = "GCS bucket for Terraform state and the Cloud Build source package (created by deploy.sh)"
}

variable "tf_source_object" {
  type        = string
  description = "Object path in tf_state_bucket for the Terraform source tarball"
  default     = "source/edge-https-lb.tgz"
}
