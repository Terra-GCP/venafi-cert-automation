resource "google_service_account" "status_app" {
  account_id   = "${var.name_prefix}-app"
  display_name = "Lab HTTPS application"
  depends_on   = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "status_app_reads_cert" {
  project   = var.project_id
  secret_id = var.secret_cert_name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.status_app.email}"
}