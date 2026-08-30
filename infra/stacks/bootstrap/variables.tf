variable "environment" {
  type = string

  validation {
    condition     = contains(["development", "production"], var.environment)
    error_message = "environment 必须是 development 或 production。"
  }
}

variable "project_id" {
  type = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id 必须是有效的 GCP Project ID。"
  }
}

variable "region" {
  type = string
}

variable "zone" {
  type = string

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone 必须属于 region。"
  }
}

variable "resource_prefix" {
  type = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,12}[a-z0-9]$", var.resource_prefix))
    error_message = "resource_prefix 必须是完整资源名前缀，且为 3-14 位小写字母、数字或连字符。"
  }
}

variable "network_cidr" {
  type = string

  validation {
    condition     = can(cidrnetmask(var.network_cidr))
    error_message = "network_cidr 必须是有效 IPv4 CIDR。"
  }
}

variable "network_tier" {
  type = string

  validation {
    condition     = contains(["PREMIUM", "STANDARD"], var.network_tier)
    error_message = "network_tier 必须是 PREMIUM 或 STANDARD。"
  }
}

variable "vm_machine_type" {
  type = string
}

variable "vm_boot_disk_gb" {
  type = number

  validation {
    condition     = var.vm_boot_disk_gb >= 10
    error_message = "vm_boot_disk_gb 不能小于 10。"
  }
}

variable "vm_source_image" {
  type = string

  validation {
    condition     = can(regex("^projects/debian-cloud/global/images/debian-12-bookworm-v[0-9]{8}$", var.vm_source_image))
    error_message = "vm_source_image 必须是 projects/debian-cloud/global/images/debian-12-bookworm-vYYYYMMDD 格式的不可变镜像。"
  }
}

variable "artifact_location" {
  type = string
}

variable "github_repository" {
  type = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository 必须是 owner/repository。"
  }
}

variable "github_repository_id" {
  type = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id 必须是不可变数字 ID。"
  }
}

variable "labels" {
  type = map(string)

  validation {
    condition = (
      lookup(var.labels, "application", "") == "proxy-builder" &&
      lookup(var.labels, "environment", "") == var.environment
    )
    error_message = "labels 必须包含正确的 application 和 environment。"
  }
}
