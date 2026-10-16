locals {
  resolved_venafi_base_url = (
    var.enable_mock
    ? google_cloud_run_v2_service.mock[0].uri
    : var.venafi_base_url
  )
  resolved_venafi_platform = var.enable_mock ? "tpp" : var.venafi_platform
  secret_exclude_prefixes = distinct(concat(
    ["${var.name_prefix}-venafi-"],
    var.secret_exclude_prefixes,
  ))
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
      timeout         = "3600s"
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
          name  = "VENAFI_TLS_VERIFY"
          value = tostring(var.venafi_tls_verify)
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
          name  = "SECRET_CERT_SUFFIX"
          value = var.secret_cert_suffix
        }
        env {
          name  = "SECRET_KEY_SUFFIX"
          value = var.secret_key_suffix
        }
        env {
          name  = "SECRET_EXCLUDE_PREFIXES"
          value = join(",", local.secret_exclude_prefixes)
        }
        env {
          name  = "VENAFI_DN_LABEL_KEY"
          value = var.venafi_dn_label_key
        }
        env {
          name  = "VENAFI_DN_PREFIX"
          value = var.venafi_dn_prefix
        }
        env {
          name  = "CREATE_SECRETS_IF_MISSING"
          value = "false"
        }
        env {
          name  = "NOTIFY_TOPIC"
          value = var.enable_pubsub_events ? google_pubsub_topic.cert_sync_events[0].name : ""
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
