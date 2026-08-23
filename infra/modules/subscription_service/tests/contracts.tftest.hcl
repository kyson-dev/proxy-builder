mock_provider "google" {}

run "startup_probe_contract" {
  command = plan

  variables {
    project_id                    = "example-project"
    environment                   = "development"
    resource_prefix               = "proxy"
    region                        = "us-west1"
    runtime_service_account_email = "subscription-runtime@example-project.iam.gserviceaccount.com"
    bootstrap_image               = "us-docker.pkg.dev/cloudrun/container/hello@sha256:9a0e9fdc0e4e959e22768f66aeda4a0e5e64cc3e981e2e5a9083af9a902da33c"
    labels                        = { application = "proxy-builder", environment = "development" }
    deploy_service_account_email  = "deploy@example-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = google_cloud_run_v2_service.subscription.template[0].containers[0].startup_probe[0].http_get[0].path == "/healthz"
    error_message = "Cloud Run startup probe 必须使用 subscription 的 /healthz 契约。"
  }

  assert {
    condition     = google_cloud_run_v2_service.subscription.template[0].containers[0].startup_probe[0].http_get[0].port == 8080
    error_message = "Cloud Run startup probe 必须检查容器端口 8080。"
  }
}
