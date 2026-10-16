output "artifact_registry" {
  value = google_artifact_registry_repository.repo.name
}

output "repo_path" {
  value = local.repo_path
}

output "enable_mock" {
  value = var.enable_mock
}

output "mock_venafi_url" {
  value = var.enable_mock ? google_cloud_run_v2_service.mock[0].uri : null
}

output "cert_sync_job" {
  value = google_cloud_run_v2_job.cert_sync.name
}

output "notify_topic" {
  value       = try(google_pubsub_topic.cert_sync_events[0].name, null)
  description = "Optional Pub/Sub events topic (null when enable_pubsub_events=false)"
}

output "venafi_secret_ids" {
  value = {
    username = google_secret_manager_secret.venafi_username.secret_id
    password = google_secret_manager_secret.venafi_password.secret_id
    p12      = google_secret_manager_secret.venafi_p12_password.secret_id
  }
}

output "sync_service_account" {
  value = google_service_account.cert_sync.email
}

output "notification_channel_ids" {
  value       = local.notification_channels
  description = "Monitoring notification channels used for renew/failure alerts"
}

output "cert_renewed_alert_policy" {
  value = try(google_monitoring_alert_policy.cert_renewed[0].name, null)
}

output "discovery" {
  value = {
    secret_cert_suffix      = var.secret_cert_suffix
    secret_key_suffix       = var.secret_key_suffix
    renew_days_before       = var.renew_days_before
    venafi_dn_label_key     = var.venafi_dn_label_key
    venafi_dn_prefix        = var.venafi_dn_prefix
    secret_exclude_prefixes = local.secret_exclude_prefixes
  }
  description = "How the sync job discovers certificates in Secret Manager"
}
