resource "google_compute_firewall" "iap_ssh" {
  project     = var.project_id
  name        = "${local.name_prefix}-allow-iap-ssh"
  network     = google_compute_network.proxy.name
  direction   = "INGRESS"
  priority    = 1000
  target_tags = [local.proxy_tag]

  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
