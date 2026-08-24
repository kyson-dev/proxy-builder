locals {
  name_prefix = var.resource_prefix

  secrets = {
    proxy_users = "${local.name_prefix}-proxy-users"
    obfs        = "${local.name_prefix}-obfs-password"
  }
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-subscription-sa"
  display_name = "Subscription runtime (${var.environment})"
  description  = "Runtime identity for the Cloud Run subscription service"
}

resource "google_secret_manager_secret" "runtime" {
  for_each = local.secrets

  project   = var.project_id
  secret_id = each.value
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_accessor" {
  for_each = google_secret_manager_secret.runtime

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "deploy_version_adder" {
  for_each = google_secret_manager_secret.runtime

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${var.deploy_service_account_email}"
}

resource "google_service_account_iam_member" "deploy_act_as" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_service_account_email}"
}
