locals {
  state_bucket_name         = "${var.project_id}-proxy-builder-tfstate"
  cloud_run_bootstrap_image = "us-docker.pkg.dev/cloudrun/container/hello@sha256:9a0e9a5c7a19281e7617991d2fc61809de4973e6e75a10b2f07df3719ffda33c"
}

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"

  config = {
    bucket = local.state_bucket_name
    prefix = "bootstrap"
  }
}

module "network" {
  source = "../../modules/network"

  project_id              = var.project_id
  environment             = var.environment
  resource_prefix         = var.resource_prefix
  region                  = var.region
  network_cidr            = var.network_cidr
  network_tier            = var.network_tier
  existing_static_ip_name = var.existing_static_ip_name
}

module "artifact_registry" {
  source = "../../modules/artifact_registry"

  project_id      = var.project_id
  environment     = var.environment
  resource_prefix = var.resource_prefix
  location        = var.region
  labels          = var.labels

  deploy_service_account_email = data.terraform_remote_state.bootstrap.outputs.deploy_service_account_email
}

module "proxy_vm" {
  source = "../../modules/proxy_vm"

  project_id           = var.project_id
  environment          = var.environment
  resource_prefix      = var.resource_prefix
  zone                 = var.zone
  machine_type         = var.vm_machine_type
  boot_disk_gb         = var.vm_boot_disk_gb
  vm_source_image      = var.vm_source_image
  network_tier         = var.network_tier
  subnetwork_self_link = module.network.subnetwork_self_link
  external_ip_address  = module.network.proxy_ip_address
  network_tag          = module.network.proxy_network_tag
  labels               = var.labels

  deploy_service_account_email = data.terraform_remote_state.bootstrap.outputs.deploy_service_account_email
}

module "secret_runtime" {
  source = "../../modules/secret_runtime"

  project_id                   = var.project_id
  environment                  = var.environment
  resource_prefix              = var.resource_prefix
  labels                       = var.labels
  deploy_service_account_email = data.terraform_remote_state.bootstrap.outputs.deploy_service_account_email
}

module "subscription_service" {
  source = "../../modules/subscription_service"

  project_id                    = var.project_id
  environment                   = var.environment
  resource_prefix               = var.resource_prefix
  region                        = var.region
  runtime_service_account_email = module.secret_runtime.runtime_service_account_email
  bootstrap_image               = local.cloud_run_bootstrap_image
  labels                        = var.labels

  deploy_service_account_email = data.terraform_remote_state.bootstrap.outputs.deploy_service_account_email
}
