output "lb_ip" {
  value = google_compute_global_address.lb.address
}

output "certificate_map" {
  value = google_certificate_manager_certificate_map.app.name
}

output "certificate_map_entry" {
  value = google_certificate_manager_certificate_map_entry.app.name
}

output "status_app_service" {
  value = google_cloud_run_v2_service.status_app.name
}

output "repo_path" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "trigger_name" {
  value = google_cloudbuild_trigger.app_https_lb.name
}

output "tf_state_bucket" {
  value = var.tf_state_bucket
}
