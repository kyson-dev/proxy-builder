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
    condition     = google_cloud_run_v2_service.subscription.template[0].containers[0].startup_probe[0].http_get[0].path == "/v1/health"
    error_message = "Cloud Run startup probe 必须使用 subscription 的 /v1/health 契约。"
  }

  assert {
    condition     = google_cloud_run_v2_service.subscription.template[0].containers[0].startup_probe[0].http_get[0].port == 8080
    error_message = "Cloud Run startup probe 必须检查容器端口 8080。"
  }

  assert {
    condition = (
      google_cloud_run_v2_service.subscription.ingress == "INGRESS_TRAFFIC_ALL" &&
      google_cloud_run_v2_service.subscription.invoker_iam_disabled == true &&
      google_cloud_run_v2_service.subscription.default_uri_disabled == false
    )
    error_message = "Cloud Run subscription 必须公开默认 URL，并由应用 token 而非 Invoker IAM 认证客户端。"
  }

  assert {
    condition     = google_logging_project_exclusion.subscription_requests.name == "proxy-subscription-request-logs"
    error_message = "日志排除名称必须从完整 resource_prefix 推导。"
  }

  assert {
    condition = alltrue([
      strcontains(google_logging_project_exclusion.subscription_requests.filter, "cloud_run_revision"),
      strcontains(google_logging_project_exclusion.subscription_requests.filter, "proxy-subscription"),
      strcontains(google_logging_project_exclusion.subscription_requests.filter, "run.googleapis.com/requests"),
    ])
    error_message = "日志排除必须只匹配当前 subscription 服务的 Cloud Run request log。"
  }
}
