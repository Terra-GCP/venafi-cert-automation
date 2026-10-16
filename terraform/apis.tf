locals {
  base_apis = [
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  apis = toset(concat(
    local.base_apis,
    var.enable_pubsub_events ? ["pubsub.googleapis.com"] : [],
  ))
}

resource "google_project_service" "apis" {
  for_each                   = local.apis
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}
