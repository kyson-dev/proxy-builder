output "workload_identity_provider" {
  value = module.github_identity.workload_identity_provider
}

output "plan_service_account_email" {
  value = module.github_identity.plan_service_account_email
}

output "apply_service_account_email" {
  value = module.github_identity.apply_service_account_email
}

output "deploy_service_account_email" {
  value = module.github_identity.deploy_service_account_email
}
