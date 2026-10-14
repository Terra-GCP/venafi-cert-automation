locals {
  resolved_venafi_base_url = (
    var.enable_mock
    ? google_cloud_run_v2_service.mock[0].uri
    : var.venafi_base_url
  )
  resolved_venafi_platform = var.enable_mock ? "tpp" : var.venafi_platform
  lab_name_prefix          = var.lab_name_prefix != "" ? var.lab_name_prefix : "${var.name_prefix}-lab"
  status_app_image         = var.status_app_image != "" ? var.status_app_image : "${local.repo_path}/cert-status-app:latest"
  use_cm_api               = var.cert_install_method == "cm_api" && var.cert_map_name != "" && var.cert_map_entry_name != ""
  use_tf_trigger           = var.cert_install_method == "tf_cloudbuild"
  resolved_tf_trigger = (
    var.enable_lab_stack
    ? google_cloudbuild_trigger.lab_https_lb[0].name
    : var.external_tf_cloudbuild_trigger
  )
}

check "tf_trigger_configured" {
  assert {
    condition     = !local.use_tf_trigger || local.resolved_tf_trigger != ""
    error_message = "tf_cloudbuild requires enable_lab_stack=true (lab trigger) or external_tf_cloudbuild_trigger set to a client-owned trigger name"
  }
}

check "real_venafi_url" {
  assert {
    condition     = var.enable_mock || var.venafi_base_url != ""
    error_message = "venafi_base_url is required when enable_mock=false"
  }
}

resource "google_cloud_run_v2_job" "cert_sync" {
  name     = "${var.name_prefix}-sync"
  location = var.region

  template {
    template {
      service_account = google_service_account.cert_sync.email
      timeout         = local.use_tf_trigger ? "1800s" : "600s"
      max_retries     = 1

      containers {
        image = local.image_sync

        env {
          name  = "VENAFI_PLATFORM"
          value = local.resolved_venafi_platform
        }
        env {
          name  = "VENAFI_BASE_URL"
          value = local.resolved_venafi_base_url
        }
        env {
          name  = "VENAFI_CERTIFICATE_DN"
          value = var.venafi_certificate_dn
        }
        env {
          name  = "VENAFI_TLS_VERIFY"
          value = tostring(var.venafi_tls_verify)
        }
        env {
          name  = "CERT_NAME"
          value = var.cert_name
        }
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "GCP_REGION"
          value = var.region
        }
        env {
          name  = "SECRET_CERT_NAME"
          value = google_secret_manager_secret.certificate.secret_id
        }
        env {
          name  = "SECRET_KEY_NAME"
          value = google_secret_manager_secret.private_key.secret_id
        }
        env {
          name  = "CREATE_SECRETS_IF_MISSING"
          value = "true"
        }
        env {
          name  = "NOTIFY_TOPIC"
          value = google_pubsub_topic.cert_sync_events.name
        }
        env {
          name  = "CERT_INSTALL_METHOD"
          value = var.cert_install_method
        }
        env {
          name  = "CERT_MAP_NAME"
          value = var.cert_map_name
        }
        env {
          name  = "CERT_MAP_ENTRY_NAME"
          value = var.cert_map_entry_name
        }
        env {
          name  = "TF_CLOUDBUILD_TRIGGER"
          value = local.resolved_tf_trigger
        }
        env {
          name  = "TF_CLOUDBUILD_TRIGGER_REGION"
          value = var.region
        }
        env {
          name  = "RENEW_ENABLED"
          value = tostring(var.renew_enabled)
        }
        env {
          name  = "RENEW_DAYS_BEFORE"
          value = tostring(var.renew_days_before)
        }
        env {
          name  = "FORCE_RENEW"
          value = tostring(var.force_renew)
        }

        env {
          name = "VENAFI_USERNAME"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.venafi_username.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "VENAFI_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.venafi_password.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "VENAFI_P12_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.venafi_p12_password.secret_id
              version = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret.venafi_username,
    google_secret_manager_secret.venafi_password,
    google_secret_manager_secret.venafi_p12_password,
  ]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}