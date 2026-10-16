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
  description = "Prefix for resource names (jobs, Venafi credential secrets, service accounts)"
  default     = "venafi-cert"
}

variable "enable_mock" {
  type        = bool
  description = "Deploy the mock Venafi TPP endpoint for dry-run environments"
  default     = false
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

variable "renew_enabled" {
  type        = bool
  description = "Call Venafi Renew before download when a sync runs"
  default     = true
}

variable "renew_days_before" {
  type        = number
  description = "Renew when a discovered Secret Manager cert has this many days (or fewer) remaining"
  default     = 30
}

variable "force_renew" {
  type        = bool
  description = "Ignore expiry window and renew every discovered cert on the next job execution"
  default     = false
}

variable "secret_cert_suffix" {
  type        = string
  description = "Secret Manager secret IDs ending with this suffix are treated as PEM certificates"
  default     = "-certificate"
}

variable "secret_key_suffix" {
  type        = string
  description = "Paired private-key secret suffix (same prefix as the certificate secret)"
  default     = "-private-key"
}

variable "secret_exclude_prefixes" {
  type        = list(string)
  description = "Skip Secret Manager secrets whose IDs start with these prefixes"
  default     = []
}

variable "venafi_dn_label_key" {
  type        = string
  description = "Secret annotation/label key for Venafi Certificate DN (fallback: CN lookup)"
  default     = "venafi-dn"
}

variable "venafi_dn_prefix" {
  type        = string
  description = "Fallback DN prefix when annotation/lookup is missing (DN = prefix\\\\CN)"
  default     = "\\\\VED\\\\Policy\\\\Apps"
}

variable "mock_initial_days_left" {
  type        = number
  description = "Days of validity for mock certs before Renew"
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
  description = "When enable_mock=true, seed mock Venafi credentials into Secret Manager. Set false for real Venafi."
  default     = true
}

variable "enable_pubsub_events" {
  type        = bool
  description = "Optional: create Pub/Sub topic and publish job results (not required for renew or email alerts)"
  default     = false
}

variable "enable_renew_alerts" {
  type        = bool
  description = "Create a Monitoring alert when a certificate is renewed"
  default     = true
}

variable "enable_failure_alerts" {
  type        = bool
  description = "Create a Monitoring alert when the sync job fails"
  default     = true
}

variable "alert_emails" {
  type        = list(string)
  description = "Email addresses for GCP Monitoring notification channels (verify each channel after create)"
  default     = []
}

variable "notification_channel_ids" {
  type        = list(string)
  description = "Existing Monitoring notification channel IDs to attach (email, PagerDuty, Slack, etc.)"
  default     = []
}
