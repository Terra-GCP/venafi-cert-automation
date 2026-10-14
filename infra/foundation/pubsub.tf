resource "google_pubsub_topic" "cert_sync_events" {
  name       = "${var.name_prefix}-events"
  depends_on = [google_project_service.apis]
}
