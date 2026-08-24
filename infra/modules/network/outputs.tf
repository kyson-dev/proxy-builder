output "network_self_link" {
  value = google_compute_network.proxy.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.proxy.self_link
}

output "proxy_ip_address" {
  value = var.existing_static_ip_name == null ? google_compute_address.proxy[0].address : data.google_compute_address.existing[0].address
}

output "proxy_network_tag" {
  value = local.proxy_tag
}

output "ingress_contract" {
  value = {
    proxy_tcp = {
      source_ranges = google_compute_firewall.proxy_tcp.source_ranges
      ports         = one(google_compute_firewall.proxy_tcp.allow).ports
    }
    proxy_udp = {
      source_ranges = google_compute_firewall.proxy_udp.source_ranges
      ports         = one(google_compute_firewall.proxy_udp.allow).ports
    }
    iap_ssh = {
      source_ranges = google_compute_firewall.iap_ssh.source_ranges
      ports         = one(google_compute_firewall.iap_ssh.allow).ports
    }
  }
}
