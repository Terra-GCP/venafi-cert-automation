output "lb_ip" {
  value = google_compute_global_address.lb.address
}

output "certificate_map" {
  value = google_certificate_manager_certificate_map.lab.name
}

output "certificate_map_entry" {
  value = google_certificate_manager_certificate_map_entry.lab.name
}

output "status_app_service" {
  value = google_cloud_run_v2_service.status_app.name
}