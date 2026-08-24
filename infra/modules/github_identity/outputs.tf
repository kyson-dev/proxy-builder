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

output "plan_wif_member" {
  value = google_service_account_iam_member.plan_wif.member
}

output "required_services" {
  value = local.required_services
}

output "apply_project_roles" {
  value = toset(values(local.project_roles.apply))
}

output "environment_isolation_contract" {
  value = {
    pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id
    service_account_ids = {
      for identity, account in google_service_account.github : identity => account.account_id
    }
    environment_wif_members = {
      for identity, binding in google_service_account_iam_member.environment_wif : identity => binding.member
    }
    state_bucket_name = var.state_bucket_name
  }
}
