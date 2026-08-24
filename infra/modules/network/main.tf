locals {
  name_prefix = var.resource_prefix
  proxy_tag   = "${local.name_prefix}-vm"
}

resource "google_compute_network" "proxy" {
  project                 = var.project_id
  name                    = "${local.name_prefix}-network"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "proxy" {
  project                  = var.project_id
  name                     = "${local.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.proxy.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true
}

data "google_compute_address" "existing" {
  count = var.existing_static_ip_name == null ? 0 : 1

  project = var.project_id
  name    = var.existing_static_ip_name
  region  = var.region
}

resource "google_compute_address" "proxy" {
  count = var.existing_static_ip_name == null ? 1 : 0

  project      = var.project_id
  name         = "${local.name_prefix}-ipv4"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = var.network_tier
}
