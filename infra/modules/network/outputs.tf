output "network_self_link" {
  value = google_compute_network.proxy.self_link
}

output "subnetwork_self_link" {
  value = google_compute_subnetwork.proxy.self_link
}

output "proxy_ip_address" {
  value = google_compute_address.proxy.address
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
