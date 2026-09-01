environment          = "production"
project_id           = "kyson-proxy-prod"
region               = "us-west1"
zone                 = "us-west1-b"
resource_prefix      = "proxy"
network_cidr         = "10.30.0.0/24"
network_tier         = "STANDARD"
vm_machine_type      = "e2-micro"
vm_boot_disk_gb      = 30
vm_source_image      = "projects/debian-cloud/global/images/debian-12-bookworm-v20260826"
github_repository    = "kyson-dev/proxy-builder"
github_repository_id = "986343343"

labels = {
  application = "proxy-builder"
  environment = "production"
}
