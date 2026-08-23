locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  repository_id     = "${var.resource_prefix}-${local.environment_short}-images"
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.location
  repository_id = local.repository_id
  description   = "proxy-builder ${var.environment} container images"
  format        = "DOCKER"
  labels        = var.labels

  docker_config {
    immutable_tags = true
  }
}

resource "google_artifact_registry_repository_iam_member" "deploy_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.deploy_service_account_email}"
}
