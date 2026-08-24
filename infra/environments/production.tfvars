environment          = "production"
project_id           = "kyson-proxy-builder"
region               = "us-west1"
zone                 = "us-west1-b"
resource_prefix      = "proxy"
network_cidr         = "10.30.0.0/24"
network_tier         = "STANDARD"
vm_machine_type      = "e2-micro"
vm_boot_disk_gb      = 10
artifact_location    = "us-west1"
github_repository    = "kyson-dev/proxy-builder"
github_repository_id = "986343343"

labels = {
  application = "proxy-builder"
  environment = "production"
}
