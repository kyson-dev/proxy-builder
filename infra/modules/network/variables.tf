variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "network_cidr" {
  type = string
}

variable "network_tier" {
  type = string
}

variable "existing_static_ip_name" {
  type     = string
  default  = null
  nullable = true

  validation {
    condition     = var.existing_static_ip_name == null || can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.existing_static_ip_name))
    error_message = "existing_static_ip_name 必须是有效的现有静态 IP 资源名称。"
  }
}
