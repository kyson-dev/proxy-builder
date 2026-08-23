mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "mocksa@example-project.iam.gserviceaccount.com"
      name  = "projects/example-project/serviceAccounts/mocksa@example-project.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789/locations/global/workloadIdentityPools/mock-pool"
    }
  }
}

run "identity_contract" {
  command = plan

  assert {
    condition     = var.github_repository_id == "986343343"
    error_message = "WIF 必须绑定不可变 GitHub repository ID。"
  }

  assert {
    condition     = var.labels["environment"] == var.environment
    error_message = "资源 label 必须匹配目标环境。"
  }

  assert {
    condition     = !contains(module.github_identity.secret_metadata_permissions, "secretmanager.versions.access")
    error_message = "apply 的 Secret Manager 自定义角色不得读取 secret payload。"
  }

  assert {
    condition     = module.github_identity.plan_wif_member == "principal://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/mock-pool/subject/repo:${var.github_repository}:pull_request"
    error_message = "plan 身份必须只允许当前仓库的 pull_request subject。"
  }

  assert {
    condition     = contains(module.github_identity.required_services, "logging.googleapis.com")
    error_message = "bootstrap 必须启用 Cloud Logging API。"
  }

  assert {
    condition     = contains(module.github_identity.apply_project_roles, "roles/logging.configWriter")
    error_message = "apply 身份必须能管理日志排除规则。"
  }

  assert {
    condition = module.github_identity.environment_isolation_contract == {
      pool_id = "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-github"
      service_account_ids = {
        plan   = "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-gh-plan"
        apply  = "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-gh-apply"
        deploy = "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-gh-deploy"
      }
      environment_wif_members = {
        apply  = "principal://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/mock-pool/subject/repo:${var.github_repository}:environment:${var.environment}"
        deploy = "principal://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/mock-pool/subject/repo:${var.github_repository}:environment:${var.environment}"
      }
      state_bucket_name = "${var.project_id}-proxy-builder-tfstate"
    }
    error_message = "WIF pool、Service Account、environment subject 与 state bucket 必须按环境隔离。"
  }
}
