resource "google_compute_firewall" "proxy_tcp" {
  project     = var.project_id
  name        = "${local.name_prefix}-allow-proxy-tcp"
  network     = google_compute_network.proxy.name
  direction   = "INGRESS"
  priority    = 1000
  target_tags = [local.proxy_tag]

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "proxy_udp" {
  project     = var.project_id
  name        = "${local.name_prefix}-allow-proxy-udp"
  network     = google_compute_network.proxy.name
  direction   = "INGRESS"
  priority    = 1000
  target_tags = [local.proxy_tag]

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "udp"
    ports    = ["443"]
  }
}
