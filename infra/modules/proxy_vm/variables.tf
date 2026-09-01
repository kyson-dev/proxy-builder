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

variable "vm_source_image" {
  type = string

  validation {
    condition     = can(regex("^projects/debian-cloud/global/images/debian-12-bookworm-v[0-9]{8}$", var.vm_source_image))
    error_message = "vm_source_image 必须是 projects/debian-cloud/global/images/debian-12-bookworm-vYYYYMMDD 格式的不可变镜像。"
  }
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
