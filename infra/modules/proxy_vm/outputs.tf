output "vm_name" {
  value = google_compute_instance.proxy.name
}

output "vm_zone" {
  value = google_compute_instance.proxy.zone
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}
