variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "deploy_service_account_email" {
  type = string
}
