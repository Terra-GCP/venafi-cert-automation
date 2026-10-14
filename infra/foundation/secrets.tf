resource "google_secret_manager_secret" "certificate" {
  secret_id = "${var.cert_name}-certificate"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "private_key" {
  secret_id = "${var.cert_name}-private-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "venafi_username" {
  secret_id = "${var.name_prefix}-venafi-username"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "venafi_password" {
  secret_id = "${var.name_prefix}-venafi-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "venafi_p12_password" {
  secret_id = "${var.name_prefix}-venafi-p12-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "venafi_username_mock" {
  count       = var.enable_mock && var.seed_mock_secret_versions ? 1 : 0
  secret      = google_secret_manager_secret.venafi_username.id
  secret_data = var.mock_username
}

resource "google_secret_manager_secret_version" "venafi_password_mock" {
  count       = var.enable_mock && var.seed_mock_secret_versions ? 1 : 0
  secret      = google_secret_manager_secret.venafi_password.id
  secret_data = var.mock_password
}

resource "google_secret_manager_secret_version" "venafi_p12_password_mock" {
  count       = var.enable_mock && var.seed_mock_secret_versions ? 1 : 0
  secret      = google_secret_manager_secret.venafi_p12_password.id
  secret_data = var.mock_p12_password
}

resource "google_secret_manager_secret_iam_member" "sync_access_creds" {
  for_each = {
    username = google_secret_manager_secret.venafi_username.id
    password = google_secret_manager_secret.venafi_password.id
    p12      = google_secret_manager_secret.venafi_p12_password.id
  }
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cert_sync.email}"
}