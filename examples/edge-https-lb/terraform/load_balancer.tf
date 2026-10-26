locals {
  placeholder_image = "us-docker.pkg.dev/cloudrun/container/hello"
  ar_status_image   = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}/edge-status-app:latest"
  status_app_image  = trimspace(var.status_app_image) != "" ? var.status_app_image : local.placeholder_image
}

resource "google_cloud_run_v2_service" "status_app" {
  name     = "${var.name_prefix}-app"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.status_app.email
    containers {
      image = local.status_app_image
      ports {
        container_port = 8080
      }
      env {
        name  = "CERT_PEM"
        value = data.google_secret_manager_secret_version.certificate.secret_data
      }
      env {
        name  = "SECRET_VERSION"
        value = data.google_secret_manager_secret_version.certificate.version
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

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
    ]
  }
}

resource "google_compute_region_network_endpoint_group" "status_app" {
  name                  = "${var.name_prefix}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.status_app.name
  }
}

resource "google_compute_backend_service" "status_app" {
  name                  = "${var.name_prefix}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = false

  backend {
    group = google_compute_region_network_endpoint_group.status_app.id
  }
}

resource "google_compute_url_map" "status_app" {
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_service.status_app.id
}

resource "google_compute_target_https_proxy" "status_app" {
  name            = "${var.name_prefix}-https-proxy"
  url_map         = google_compute_url_map.status_app.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.app.id}"
}

resource "google_compute_global_address" "lb" {
  name = "${var.name_prefix}-ip"
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.name_prefix}-https"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.status_app.id
  ip_address            = google_compute_global_address.lb.id
}

resource "google_cloud_run_v2_service_iam_member" "lb_invokes_status_app" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.status_app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}