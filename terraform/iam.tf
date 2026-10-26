resource "google_service_account" "cert_sync" {
  account_id   = "${var.name_prefix}-sync"
  display_name = "Venafi certificate sync job"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "mock" {
  count        = var.enable_mock ? 1 : 0
  account_id   = "${var.name_prefix}-mock"
  display_name = "Venafi mock TPP API"
  depends_on   = [google_project_service.apis]
}

resource "google_service_account" "scheduler" {
  account_id   = "${var.name_prefix}-sched"
  display_name = "Venafi certificate sync scheduler"
  depends_on   = [google_project_service.apis]
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "cert_sync_secret_roles" {
  for_each = toset([
    "roles/secretmanager.viewer",
    "roles/secretmanager.secretAccessor",
    "roles/secretmanager.secretVersionAdder",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_pubsub_topic_iam_member" "cert_sync_pubsub" {
  count  = var.enable_pubsub_events ? 1 : 0
  topic  = google_pubsub_topic.cert_sync_events[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_project_iam_member" "build_roles" {
  for_each = {
    for pair in setproduct(
      [
        "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com",
        "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com",
      ],
      [
        "roles/artifactregistry.writer",
        "roles/logging.logWriter",
      ]
    ) : "${pair[0]}-${pair[1]}" => { member = pair[0], role = pair[1] }
  }
  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

resource "google_cloud_run_v2_service_iam_member" "mock_invoked_by_sync" {
  count    = var.enable_mock ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.mock[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_job" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.cert_sync.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}
