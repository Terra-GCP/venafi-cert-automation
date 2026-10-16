resource "google_cloud_scheduler_job" "daily_sync" {
  name             = "${var.name_prefix}-daily"
  description      = "Daily Venafi certificate sync"
  schedule         = var.scheduler_cron
  time_zone        = var.scheduler_timezone
  attempt_deadline = "320s"
  region           = var.region

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.cert_sync.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_project_service.apis]
}