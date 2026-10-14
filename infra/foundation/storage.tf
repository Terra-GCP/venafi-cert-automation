resource "google_storage_bucket" "tf" {
  name                        = "${var.project_id}-${var.name_prefix}-tf"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "build_tf_admin" {
  for_each = toset([
    "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com",
    "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com",
  ])
  bucket = google_storage_bucket.tf.name
  role   = "roles/storage.objectAdmin"
  member = each.value
}

resource "google_storage_bucket_iam_member" "sync_tf_viewer" {
  bucket = google_storage_bucket.tf.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cert_sync.email}"
}