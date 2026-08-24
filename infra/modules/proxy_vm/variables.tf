variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "zone" {
  type = string
}

variable "machine_type" {
  type = string
}

variable "boot_disk_gb" {
  type = number
}

variable "network_tier" {
  type = string
}

variable "subnetwork_self_link" {
  type = string
}

variable "external_ip_address" {
  type = string
}

variable "network_tag" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "deploy_service_account_email" {
  type = string
}
