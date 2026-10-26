locals {
  sync_job_name      = "${var.name_prefix}-sync"
  has_alert_channels = length(var.alert_emails) > 0 || length(var.notification_channel_ids) > 0
  created_email_channels = [
    for ch in google_monitoring_notification_channel.email : ch.id
  ]
  notification_channels = distinct(concat(var.notification_channel_ids, local.created_email_channels))
  renew_log_filter      = <<-EOT
    resource.type="cloud_run_job"
    resource.labels.job_name="${local.sync_job_name}"
    jsonPayload.message="VENAFI_CERT_EVENT"
    jsonPayload.status="renewed"
  EOT
  fail_log_filter       = <<-EOT
    resource.type="cloud_run_job"
    resource.labels.job_name="${local.sync_job_name}"
    jsonPayload.message="VENAFI_CERT_EVENT"
    jsonPayload.status="failed"
  EOT
}

resource "google_monitoring_notification_channel" "email" {
  for_each     = toset(var.alert_emails)
  display_name = "${var.name_prefix} renew alert (${each.value})"
  type         = "email"
  labels = {
    email_address = each.value
  }
  force_delete = false
}

resource "google_monitoring_alert_policy" "cert_renewed" {
  count        = var.enable_renew_alerts && local.has_alert_channels ? 1 : 0
  display_name = "${var.name_prefix} certificate renewed"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = <<-EOT
      Certificate renewed and written to Secret Manager.

      Fields: cert_name, subject, expiry, secret_cert, secret_cert_version, summary.

      Query: `jsonPayload.message="VENAFI_CERT_EVENT" AND jsonPayload.status="renewed"`
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "VENAFI_CERT_EVENT status=renewed"
    condition_matched_log {
      filter = local.renew_log_filter
      label_extractors = {
        cert_name           = "EXTRACT(jsonPayload.cert_name)"
        subject             = "EXTRACT(jsonPayload.subject)"
        expiry              = "EXTRACT(jsonPayload.expiry)"
        secret_cert         = "EXTRACT(jsonPayload.secret_cert)"
        secret_cert_version = "EXTRACT(jsonPayload.secret_cert_version)"
        summary             = "EXTRACT(jsonPayload.summary)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "604800s"
  }

  notification_channels = local.notification_channels

  depends_on = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "cert_failed" {
  count        = var.enable_failure_alerts && local.has_alert_channels ? 1 : 0
  display_name = "${var.name_prefix} certificate sync failed"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = <<-EOT
      Certificate sync failed.

      Fields: cert_name, failed_at, error, summary.

      Query: `jsonPayload.message="VENAFI_CERT_EVENT" AND jsonPayload.status="failed"`
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "VENAFI_CERT_EVENT status=failed"
    condition_matched_log {
      filter = local.fail_log_filter
      label_extractors = {
        cert_name = "EXTRACT(jsonPayload.cert_name)"
        failed_at = "EXTRACT(jsonPayload.failed_at)"
        error     = "EXTRACT(jsonPayload.error)"
        summary   = "EXTRACT(jsonPayload.summary)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "604800s"
  }

  notification_channels = local.notification_channels

  depends_on = [google_project_service.apis]
}
