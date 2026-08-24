mock_provider "google" {
  mock_data "google_compute_address" {
    defaults = {
      address = "198.51.100.20"
    }
  }

  mock_resource "google_compute_address" {
    defaults = {
      address = "198.51.100.10"
    }
  }

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
    condition     = module.network.proxy_network_tag == "${var.resource_prefix}-vm"
    error_message = "proxy network tag 必须从完整 resource_prefix 派生。"
  }

  assert {
    condition     = module.artifact_registry.repository_id == "${var.resource_prefix}-images"
    error_message = "Artifact Registry 名称必须从完整 resource_prefix 派生。"
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

  assert {
    condition     = output.proxy_host_bootstrap_sha256 == module.proxy_vm.host_bootstrap_sha256
    error_message = "platform 必须公开 VM host bootstrap 摘要。"
  }


  assert {
    condition     = output.subscription_request_log_exclusion_name == "${var.resource_prefix}-subscription-request-logs"
    error_message = "platform 必须公开从完整 resource_prefix 派生的 subscription 请求日志排除名称。"
  }
}

run "platform_uses_supplied_static_ip" {
  command = plan

  variables {
    existing_static_ip_name = "legacy-ipv4"
  }

  assert {
    condition     = output.proxy_ip_address == "198.51.100.20"
    error_message = "指定 existing_static_ip_name 时 VM 必须使用读取到的静态 IP。"
  }
}
