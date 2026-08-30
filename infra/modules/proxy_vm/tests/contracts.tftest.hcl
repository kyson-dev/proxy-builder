mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "proxy-runtime@example-project.iam.gserviceaccount.com"
      name  = "projects/example-project/serviceAccounts/proxy-runtime@example-project.iam.gserviceaccount.com"
    }
  }
}

run "startup_metadata_contract" {
  command = plan

  variables {
    project_id                   = "example-project"
    environment                  = "development"
    resource_prefix              = "proxy"
    zone                         = "us-west1-b"
    machine_type                 = "e2-micro"
    boot_disk_gb                 = 10
    vm_source_image              = "projects/debian-cloud/global/images/debian-12-bookworm-v20260826"
    network_tier                 = "STANDARD"
    subnetwork_self_link         = "projects/example-project/regions/us-west1/subnetworks/proxy-subnet"
    external_ip_address          = "203.0.113.10"
    network_tag                  = "proxy-vm"
    labels                       = { application = "proxy-builder", environment = "development" }
    deploy_service_account_email = "proxy-gh-deploy@example-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = google_compute_instance.proxy.boot_disk[0].initialize_params[0].image == var.vm_source_image
    error_message = "VM 启动盘必须使用环境显式提供的不可变 Debian 镜像。"
  }

  assert {
    condition     = google_compute_instance.proxy.metadata["startup-script"] == file("${path.module}/files/startup.sh")
    error_message = "VM startup-script metadata 必须来自受版本控制的主机供给脚本。"
  }

  assert {
    condition     = google_compute_instance.proxy.metadata["proxy-bootstrap-sha256"] == sha256(file("${path.module}/files/startup.sh"))
    error_message = "VM 必须发布 startup script 的 SHA-256 供部署前校验。"
  }

  assert {
    condition = (
      google_service_account_iam_member.deploy_act_as.role == "roles/iam.serviceAccountUser" &&
      google_service_account_iam_member.deploy_act_as.member == "serviceAccount:${var.deploy_service_account_email}"
    )
    error_message = "deploy 身份必须只能 actAs 当前环境的 VM runtime service account。"
  }

  assert {
    condition     = google_service_account.runtime.account_id == "proxy-vm-sa"
    error_message = "VM runtime service account 必须使用完整 resource_prefix 的 proxy-vm-sa 命名。"
  }
}

run "rejects_image_family" {
  command = plan

  variables {
    project_id                   = "example-project"
    environment                  = "development"
    resource_prefix              = "proxy"
    zone                         = "us-west1-b"
    machine_type                 = "e2-micro"
    boot_disk_gb                 = 10
    vm_source_image              = "projects/debian-cloud/global/images/family/debian-12"
    network_tier                 = "STANDARD"
    subnetwork_self_link         = "projects/example-project/regions/us-west1/subnetworks/proxy-subnet"
    external_ip_address          = "203.0.113.10"
    network_tag                  = "proxy-vm"
    labels                       = { application = "proxy-builder", environment = "development" }
    deploy_service_account_email = "proxy-gh-deploy@example-project.iam.gserviceaccount.com"
  }

  expect_failures = [var.vm_source_image]
}
