resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.name_prefix
  description   = "Venafi certificate automation container images"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

locals {
  placeholder_image = "us-docker.pkg.dev/cloudrun/container/hello"
  repo_path         = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
  image_sync        = trimspace(var.image_sync) != "" ? var.image_sync : local.placeholder_image
  image_mock        = trimspace(var.image_mock) != "" ? var.image_mock : local.placeholder_image
}