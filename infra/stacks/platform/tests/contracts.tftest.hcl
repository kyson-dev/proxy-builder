mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "mocksa@example-project.iam.gserviceaccount.com"
      name  = "projects/example-project/serviceAccounts/mocksa@example-project.iam.gserviceaccount.com"
    }
  }
}

override_data {
  target = data.terraform_remote_state.bootstrap
  values = {
    outputs = {
      deploy_service_account_email = "proxy-deploy@example-project.iam.gserviceaccount.com"
    }
  }
}

run "platform_contract" {
  command = plan

  assert {
    condition     = module.network.proxy_network_tag == "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-proxy"
    error_message = "proxy network tag 必须包含环境缩写。"
  }

  assert {
    condition     = module.artifact_registry.repository_id == "${var.resource_prefix}-${var.environment == "production" ? "prod" : "dev"}-images"
    error_message = "Artifact Registry 名称必须包含环境缩写。"
  }

  assert {
    condition = (
      module.network.ingress_contract.proxy_tcp.source_ranges == toset(["0.0.0.0/0"]) &&
      toset(module.network.ingress_contract.proxy_tcp.ports) == toset(["443"]) &&
      module.network.ingress_contract.proxy_udp.source_ranges == toset(["0.0.0.0/0"]) &&
      toset(module.network.ingress_contract.proxy_udp.ports) == toset(["443"])
    )
    error_message = "公网代理规则只能开放 TCP/UDP 443。"
  }

  assert {
    condition = (
      module.network.ingress_contract.iap_ssh.source_ranges == toset(["35.235.240.0/20"]) &&
      toset(module.network.ingress_contract.iap_ssh.ports) == toset(["22"])
    )
    error_message = "SSH 只能从 IAP 地址段进入。"
  }
}
