locals {
  environment_short = var.environment == "production" ? "prod" : "dev"
  name_prefix       = "${var.resource_prefix}-${local.environment_short}"
  proxy_tag         = "${local.name_prefix}-proxy"
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

resource "google_compute_address" "proxy" {
  project      = var.project_id
  name         = "${local.name_prefix}-ipv4"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = var.network_tier
}
