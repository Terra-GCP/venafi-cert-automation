variable "project_id" {
  type        = string
  description = "GCP project ID where the automation is deployed"
}

variable "region" {
  type        = string
  description = "Primary GCP region for Cloud Run, Artifact Registry, Scheduler, and Cloud Build"
  default     = "us-central1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names (jobs, secrets, triggers, service accounts)"
  default     = "venafi-cert"
}

variable "cert_name" {
  type        = string
  description = "Logical name for the primary certificate (drives Secret Manager IDs)"
  default     = "app-tls"
}

variable "cert_common_name" {
  type        = string
  description = "Common Name used for mock issuance and lab near-expiry seed material"
  default     = "app.example.local"
}

variable "secondary_cert_name" {
  type        = string
  description = "Optional second logical cert name for lab near-expiry seeding only (empty to skip)"
  default     = ""
}

variable "secondary_cert_common_name" {
  type        = string
  description = "Common Name for the secondary seeded certificate"
  default     = "edge.example.local"
}

variable "enable_mock" {
  type        = bool
  description = "Deploy the mock Venafi TPP endpoint for lab and dry-run environments"
  default     = true
}

variable "venafi_platform" {
  type        = string
  description = "Venafi platform when enable_mock=false: tpp | cloud"
  default     = "tpp"
}

variable "venafi_base_url" {
  type        = string
  description = "Venafi Trust Protection Platform base URL when enable_mock=false"
  default     = ""
}

variable "venafi_certificate_dn" {
  type        = string
  description = "Certificate DN in Venafi (TPP path) or mock default DN"
  default     = "\\\\VED\\\\Policy\\\\Apps\\\\app.example.local"
}

variable "venafi_tls_verify" {
  type        = bool
  description = "Verify TLS when calling Venafi"
  default     = true
}

variable "scheduler_cron" {
  type        = string
  description = "Cloud Scheduler cron for the daily sync job"
  default     = "0 6 * * *"
}

variable "scheduler_timezone" {
  type        = string
  description = "Timezone for the scheduler cron"
  default     = "UTC"
}

variable "image_mock" {
  type        = string
  description = "Override mock Venafi image URI (defaults to Artifact Registry)"
  default     = ""
}

variable "image_sync" {
  type        = string
  description = "Override cert-sync image URI (defaults to Artifact Registry)"
  default     = ""
}

variable "cert_map_name" {
  type        = string
  description = "Certificate Manager map name used by cm_api install"
  default     = ""
}

variable "cert_map_entry_name" {
  type        = string
  description = "Certificate Manager map entry name used by cm_api install"
  default     = ""
}

variable "renew_enabled" {
  type        = bool
  description = "Call Venafi Renew before download when a sync runs"
  default     = true
}

variable "renew_days_before" {
  type        = number
  description = "Renew when Secret Manager cert has this many days (or fewer) remaining"
  default     = 30
}

variable "force_renew" {
  type        = bool
  description = "Ignore expiry window and renew on the next job execution"
  default     = false
}

variable "mock_initial_days_left" {
  type        = number
  description = "Days of validity for mock certs before Renew (positive near-expiry; negative = already expired)"
  default     = 7
}

variable "mock_renew_validity_days" {
  type        = number
  description = "Days of validity for mock certs after Renew"
  default     = 90
}

variable "mock_username" {
  type        = string
  description = "Username accepted by the mock Venafi service"
  default     = "mock-user"
}

variable "mock_password" {
  type        = string
  description = "Password accepted by the mock Venafi service"
  default     = "mock-password"
  sensitive   = true
}

variable "mock_p12_password" {
  type        = string
  description = "PKCS#12 password used by the mock Venafi service"
  default     = "changeit"
  sensitive   = true
}

variable "seed_mock_secret_versions" {
  type        = bool
  description = "Write mock Venafi credentials into Secret Manager (disable for real Venafi)"
  default     = true
}

variable "enable_lab_stack" {
  type        = bool
  description = "Enable optional lab verification resources (near-expiry seed helpers, lab HTTPS LB Cloud Build trigger). Keep false for client/production."
  default     = false
}

variable "seed_expired_certificates" {
  type        = bool
  description = "LAB ONLY. Write near-expiry cert/key material into Secret Manager for renew demos. Must stay false for client environments that already have certificates."
  default     = false
}

variable "seed_days_until_expiry" {
  type        = number
  description = "LAB ONLY. Days remaining on seeded certificates (keep <= renew_days_before so the next sync renews without force)"
  default     = 7
}

variable "cert_install_method" {
  type        = string
  description = "How the sync job installs a renewed cert: cm_api | tf_cloudbuild | none"
  default     = "cm_api"

  validation {
    condition     = contains(["cm_api", "tf_cloudbuild", "none"], var.cert_install_method)
    error_message = "cert_install_method must be cm_api, tf_cloudbuild, or none"
  }
}

variable "tf_source_object" {
  type        = string
  description = "Object path in the TF state bucket for the lab HTTPS LB package (lab stack only)"
  default     = "source/lab-https-lb.tgz"
}

variable "lab_name_prefix" {
  type        = string
  description = "name_prefix used by infra/lab-https-lb (defaults to name_prefix-lab)"
  default     = ""
}

variable "status_app_image" {
  type        = string
  description = "Lab cert-status app image (defaults to Artifact Registry cert-status-app:latest)"
  default     = ""
}

variable "external_tf_cloudbuild_trigger" {
  type        = string
  description = "Existing Cloud Build trigger name for tf_cloudbuild install when lab stack is disabled (client-owned Terraform)"
  default     = ""
}