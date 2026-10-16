resource "google_service_account" "status_app" {
  account_id   = "${var.name_prefix}-app"
  display_name = "Example HTTPS status application"
  depends_on   = [google_project_service.apis]
}