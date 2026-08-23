locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  service_name      = "${var.resource_prefix}-${local.environment_short}-subscription"
}

resource "google_cloud_run_v2_service" "subscription" {
  project             = var.project_id
  name                = local.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = var.labels

  template {
    service_account                  = var.runtime_service_account_email
    timeout                          = "30s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = var.bootstrap_image

      ports {
        container_port = 8080
      }

      resources {
        cpu_idle          = true
        startup_cpu_boost = true
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].env,
      template[0].containers[0].image,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = google_cloud_run_v2_service.subscription.location
  name     = google_cloud_run_v2_service.subscription.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "deploy" {
  project  = var.project_id
  location = google_cloud_run_v2_service.subscription.location
  name     = google_cloud_run_v2_service.subscription.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${var.deploy_service_account_email}"
}
