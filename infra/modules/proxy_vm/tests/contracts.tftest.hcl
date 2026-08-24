mock_provider "google" {
  mock_data "google_compute_image" {
    defaults = {
      self_link = "projects/debian-cloud/global/images/debian-12-mock"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      email = "proxy-runtime@example-project.iam.gserviceaccount.com"
    }
  }
}

run "startup_metadata_contract" {
  command = plan

  variables {
    project_id           = "example-project"
    environment          = "development"
    resource_prefix      = "proxy"
    zone                 = "us-west1-b"
    machine_type         = "e2-micro"
    boot_disk_gb         = 10
    network_tier         = "STANDARD"
    subnetwork_self_link = "projects/example-project/regions/us-west1/subnetworks/proxy-dev"
    external_ip_address  = "203.0.113.10"
    network_tag          = "proxy-dev-proxy"
    labels               = { application = "proxy-builder", environment = "development" }
  }

  assert {
    condition     = google_compute_instance.proxy.metadata["startup-script"] == file("${path.module}/files/startup.sh")
    error_message = "VM startup-script metadata 必须来自受版本控制的主机供给脚本。"
  }

  assert {
    condition     = google_compute_instance.proxy.metadata["proxy-bootstrap-sha256"] == sha256(file("${path.module}/files/startup.sh"))
    error_message = "VM 必须发布 startup script 的 SHA-256 供部署前校验。"
  }
}
