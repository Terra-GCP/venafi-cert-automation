data "google_secret_manager_secret_version" "certificate" {
  secret  = var.secret_cert_name
  project = var.project_id
}

data "google_secret_manager_secret_version" "private_key" {
  secret  = var.secret_key_name
  project = var.project_id
}

resource "random_id" "certificate" {
  byte_length = 2
  keepers = {
    cert = data.google_secret_manager_secret_version.certificate.secret_data
    key  = data.google_secret_manager_secret_version.private_key.secret_data
  }
}

resource "google_certificate_manager_certificate" "lab" {
  name        = "${var.name_prefix}-${random_id.certificate.hex}"
  description = "Certificate material loaded from Secret Manager"
  scope       = "DEFAULT"

  self_managed {
    pem_certificate = data.google_secret_manager_secret_version.certificate.secret_data
    pem_private_key = data.google_secret_manager_secret_version.private_key.secret_data
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.apis]
}

resource "google_certificate_manager_certificate_map" "lab" {
  name       = "${var.name_prefix}-map"
  depends_on = [google_project_service.apis]
}

resource "google_certificate_manager_certificate_map_entry" "lab" {
  name         = "${var.name_prefix}-entry"
  map          = google_certificate_manager_certificate_map.lab.name
  certificates = [google_certificate_manager_certificate.lab.id]
  matcher      = "PRIMARY"
}