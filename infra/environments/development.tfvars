environment          = "development"
project_id           = "kyson-proxy-dev"
region               = "asia-northeast3"
zone                 = "asia-northeast3-a"
resource_prefix      = "proxy"
network_cidr         = "10.20.0.0/24"
network_tier         = "STANDARD"
vm_machine_type      = "e2-micro"
vm_boot_disk_gb      = 10
vm_source_image      = "projects/debian-cloud/global/images/debian-12-bookworm-v20260826"
artifact_location    = "asia-northeast3"
github_repository    = "kyson-dev/proxy-builder"
github_repository_id = "986343343"

labels = {
  application = "proxy-builder"
  environment = "development"
}
