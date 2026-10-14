variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Region for the Cloud Run lab service and NEG"
  default     = "us-central1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for lab load balancer and Certificate Manager resources"
  default     = "venafi-cert-lab"
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
  description = "Container image for the lab HTTPS application"
}