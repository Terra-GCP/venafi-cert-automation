output "artifact_registry" {
  value = google_artifact_registry_repository.repo.name
}

output "repo_path" {
  value = local.repo_path
}

output "enable_mock" {
  value = var.enable_mock
}

output "enable_lab_stack" {
  value = var.enable_lab_stack
}

output "mock_venafi_url" {
  value = var.enable_mock ? google_cloud_run_v2_service.mock[0].uri : null
}

output "cert_sync_job" {
  value = google_cloud_run_v2_job.cert_sync.name
}

output "notify_topic" {
  value = google_pubsub_topic.cert_sync_events.name
}

output "secret_cert_name" {
  value = google_secret_manager_secret.certificate.secret_id
}

output "secret_key_name" {
  value = google_secret_manager_secret.private_key.secret_id
}

output "secondary_secret_cert_name" {
  value = try(google_secret_manager_secret.secondary_certificate[0].secret_id, null)
}

output "secondary_secret_key_name" {
  value = try(google_secret_manager_secret.secondary_private_key[0].secret_id, null)
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

output "tf_bucket" {
  value = google_storage_bucket.tf.name
}

output "tf_source_object" {
  value = var.tf_source_object
}

output "cert_install_method" {
  value = var.cert_install_method
}

output "lab_tf_trigger" {
  value = try(google_cloudbuild_trigger.lab_https_lb[0].name, null)
}

output "lab_tf_trigger_region" {
  value = var.enable_lab_stack ? var.region : null
}

output "resolved_tf_trigger" {
  value = local.resolved_tf_trigger != "" ? local.resolved_tf_trigger : null
}
