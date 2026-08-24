output "proxy_ip_address" {
  value = module.network.proxy_ip_address
}

output "proxy_vm_name" {
  value = module.proxy_vm.vm_name
}

output "proxy_vm_zone" {
  value = module.proxy_vm.vm_zone
}

output "proxy_host_bootstrap_sha256" {
  value = module.proxy_vm.host_bootstrap_sha256
}

output "artifact_repository_url" {
  value = module.artifact_registry.repository_url
}

output "subscription_service_name" {
  value = module.subscription_service.service_name
}

output "subscription_service_url" {
  value = module.subscription_service.service_url
}

output "subscription_request_log_exclusion_name" {
  value = module.subscription_service.request_log_exclusion_name
}

output "proxy_users_secret_id" {
  value = module.secret_runtime.proxy_users_secret_id
}

output "obfs_password_secret_id" {
  value = module.secret_runtime.obfs_password_secret_id
}
