locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  name_prefix       = "${var.resource_prefix}-${local.environment_short}"
  startup_script    = file("${path.module}/files/startup.sh")
  startup_sha256    = sha256(local.startup_script)
}

data "google_compute_image" "debian" {
  project = "debian-cloud"
  family  = "debian-12"
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "${local.name_prefix}-proxy"
  display_name = "Proxy runtime (${var.environment})"
  description  = "Runtime identity for the proxy VM; no project roles"
}

resource "google_compute_instance" "proxy" {
  project                   = var.project_id
  name                      = "${local.name_prefix}-vm"
  zone                      = var.zone
  machine_type              = var.machine_type
  allow_stopping_for_update = true
  deletion_protection       = false
  tags                      = [var.network_tag]
  labels                    = var.labels

  boot_disk {
    auto_delete = true

    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = var.boot_disk_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnetwork_self_link

    access_config {
      nat_ip       = var.external_ip_address
      network_tier = var.network_tier
    }
  }

  metadata = {
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "TRUE"
    proxy-bootstrap-sha256 = local.startup_sha256
    startup-script         = local.startup_script
  }

  service_account {
    email  = google_service_account.runtime.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }
}
