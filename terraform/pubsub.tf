resource "google_pubsub_topic" "cert_sync_events" {
  count      = var.enable_pubsub_events ? 1 : 0
  name       = "${var.name_prefix}-events"
  depends_on = [google_project_service.apis]
}
