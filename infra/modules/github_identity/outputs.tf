output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account_email" {
  value = google_service_account.github["plan"].email
}

output "apply_service_account_email" {
  value = google_service_account.github["apply"].email
}

output "deploy_service_account_email" {
  value = google_service_account.github["deploy"].email
}

output "secret_metadata_permissions" {
  value = google_project_iam_custom_role.secret_metadata_admin.permissions
}
