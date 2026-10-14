resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.name_prefix
  description   = "Venafi certificate automation container images"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

locals {
  repo_path  = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
  image_mock = coalesce(var.image_mock, "${local.repo_path}/mock-venafi:latest")
  image_sync = coalesce(var.image_sync, "${local.repo_path}/cert-sync:latest")
}