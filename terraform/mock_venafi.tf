resource "google_cloud_run_v2_service" "mock" {
  count    = var.enable_mock ? 1 : 0
  name     = "${var.name_prefix}-mock"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.mock[0].email
    containers {
      image = local.image_mock
      env {
        name  = "MOCK_VENAFI_USER"
        value = var.mock_username
      }
      env {
        name  = "MOCK_VENAFI_PASSWORD"
        value = var.mock_password
      }
      env {
        name  = "MOCK_P12_PASSWORD"
        value = var.mock_p12_password
      }
      env {
        name  = "MOCK_INITIAL_DAYS_LEFT"
        value = tostring(var.mock_initial_days_left)
      }
      env {
        name  = "MOCK_RENEW_VALIDITY_DAYS"
        value = tostring(var.mock_renew_validity_days)
      }
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}
