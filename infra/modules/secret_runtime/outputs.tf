output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "proxy_users_secret_id" {
  value = google_secret_manager_secret.runtime["proxy_users"].secret_id
}

output "obfs_password_secret_id" {
  value = google_secret_manager_secret.runtime["obfs"].secret_id
}
