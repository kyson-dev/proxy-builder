locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  name_prefix       = "${var.resource_prefix}-${local.environment_short}"
  environment_sub   = "repo:${var.github_repository}:environment:${var.environment}"

  required_services = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "oslogin.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
    "storage.googleapis.com",
  ])

  service_accounts = {
    plan = {
      account_id   = "${local.name_prefix}-gh-plan"
      display_name = "GitHub plan (${var.environment})"
    }
    apply = {
      account_id   = "${local.name_prefix}-gh-apply"
      display_name = "GitHub apply (${var.environment})"
    }
    deploy = {
      account_id   = "${local.name_prefix}-gh-deploy"
      display_name = "GitHub deploy (${var.environment})"
    }
  }

  project_roles = {
    plan = toset([
      "roles/viewer",
    ])
    apply = toset([
      "roles/artifactregistry.admin",
      "roles/compute.admin",
      "roles/iam.roleAdmin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/iam.workloadIdentityPoolAdmin",
      "roles/resourcemanager.projectIamAdmin",
      "roles/run.admin",
      google_project_iam_custom_role.secret_metadata_admin.name,
      "roles/serviceusage.serviceUsageAdmin",
    ])
    deploy = toset([
      "roles/compute.osAdminLogin",
      "roles/compute.viewer",
      "roles/iap.tunnelResourceAccessor",
    ])
  }

  project_role_bindings = flatten([
    for identity, roles in local.project_roles : [
      for role in roles : {
        key      = "${identity}:${role}"
        identity = identity
        role     = role
      }
    ]
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "github" {
  for_each = local.service_accounts

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
  description  = "Managed by OpenTofu for proxy-builder"

  depends_on = [google_project_service.required]
}

resource "google_project_iam_custom_role" "secret_metadata_admin" {
  project     = var.project_id
  role_id     = "${replace(title(var.resource_prefix), "-", "")}${title(local.environment_short)}SecretMetadataAdmin"
  title       = "Proxy secret metadata admin (${var.environment})"
  description = "Manage Secret Manager containers and IAM without reading payloads"
  stage       = "GA"

  permissions = [
    "resourcemanager.projects.get",
    "resourcemanager.projects.list",
    "secretmanager.locations.get",
    "secretmanager.locations.list",
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.list",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.secrets.update",
  ]

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${local.name_prefix}-github"
  display_name              = "GitHub ${var.environment}"
  description               = "GitHub Actions identities for proxy-builder ${var.environment}"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"
  description                        = "GitHub Actions from the immutable repository ID"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.event_name"          = "assertion.event_name"
    "attribute.ref"                 = "assertion.ref"
  }
  attribute_condition = "assertion.repository_id == '${var.github_repository_id}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.github["plan"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github_repository_id}"
}

resource "google_service_account_iam_member" "environment_wif" {
  for_each = toset(["apply", "deploy"])

  service_account_id = google_service_account.github[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${local.environment_sub}"
}

resource "google_project_iam_member" "github" {
  for_each = { for binding in local.project_role_bindings : binding.key => binding }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.github[each.value.identity].email}"
}

resource "google_storage_bucket_iam_member" "state_writer" {
  for_each = toset(["plan", "apply"])

  bucket = var.state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github[each.value].email}"
}

resource "google_storage_bucket_iam_member" "state_reader" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.github["deploy"].email}"
}
