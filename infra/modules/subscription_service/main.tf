locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  service_name      = "${var.resource_prefix}-${local.environment_short}-subscription"
}

resource "google_cloud_run_v2_service" "subscription" {
  project              = var.project_id
  name                 = local.service_name
  location             = var.region
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = true
  default_uri_disabled = false
  deletion_protection  = false
  labels               = var.labels

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

      startup_probe {
        failure_threshold     = 10
        initial_delay_seconds = 0
        period_seconds        = 3
        timeout_seconds       = 2

        http_get {
          path = "/v1/health"
          port = 8080
        }
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
      client,
      client_version,
      template[0].containers[0].env,
      template[0].containers[0].image,
      traffic,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "deploy" {
  project  = var.project_id
  location = google_cloud_run_v2_service.subscription.location
  name     = google_cloud_run_v2_service.subscription.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${var.deploy_service_account_email}"
}

# Subscription credentials are query parameters for client compatibility.
# Cloud Run request logs include requestUrl, so suppress the platform-generated
# request log for this service and rely on the application's sanitized JSON log.
resource "google_logging_project_exclusion" "subscription_requests" {
  project     = var.project_id
  name        = "${local.service_name}-request-logs"
  description = "Exclude Cloud Run request URLs that may contain subscription tokens"
  filter      = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${local.service_name}"
    log_id("run.googleapis.com/requests")
  EOT
}
