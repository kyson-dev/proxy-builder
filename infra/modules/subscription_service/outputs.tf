output "service_name" {
  value = google_cloud_run_v2_service.subscription.name
}

output "service_url" {
  value = google_cloud_run_v2_service.subscription.uri
}

output "request_log_exclusion_name" {
  value = google_logging_project_exclusion.subscription_requests.name
}
