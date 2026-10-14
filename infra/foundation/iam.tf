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

resource "google_project_iam_member" "cert_sync_secret_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_project_iam_member" "cert_sync_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_project_iam_member" "cert_sync_cert_manager" {
  count   = var.cert_install_method == "cm_api" ? 1 : 0
  project = var.project_id
  role    = "roles/certificatemanager.editor"
  member  = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_project_iam_member" "cert_sync_cloudbuild" {
  count   = var.cert_install_method == "tf_cloudbuild" ? 1 : 0
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.cert_sync.email}"
}

resource "google_service_account_iam_member" "sync_act_as_trigger_sa" {
  count              = var.cert_install_method == "tf_cloudbuild" ? 1 : 0
  service_account_id = "projects/${var.project_id}/serviceAccounts/${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cert_sync.email}"
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  build_executor_sas = toset([
    "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com",
    "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com",
  ])
}

resource "google_project_iam_member" "build_secret_accessor" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/secretmanager.secretAccessor"
  member   = each.value
}

resource "google_project_iam_member" "build_secret_admin" {
  for_each = var.enable_lab_stack ? local.build_executor_sas : toset([])
  project  = var.project_id
  role     = "roles/secretmanager.admin"
  member   = each.value
}

resource "google_project_iam_member" "build_cert_manager" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/certificatemanager.editor"
  member   = each.value
}

resource "google_project_iam_member" "build_compute_admin" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/compute.admin"
  member   = each.value
}

resource "google_project_iam_member" "build_sa_admin" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/iam.serviceAccountAdmin"
  member   = each.value
}

resource "google_project_iam_member" "build_artifact_writer" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/artifactregistry.writer"
  member   = each.value
}

resource "google_project_iam_member" "build_run_admin" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/run.admin"
  member   = each.value
}

resource "google_project_iam_member" "build_sa_user" {
  for_each = local.build_executor_sas
  project  = var.project_id
  role     = "roles/iam.serviceAccountUser"
  member   = each.value
}

resource "google_cloud_run_v2_service_iam_member" "mock_public" {
  count    = var.enable_mock ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.mock[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_job" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.cert_sync.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}