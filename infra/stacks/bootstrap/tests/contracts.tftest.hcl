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
}
