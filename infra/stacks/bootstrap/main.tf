module "github_identity" {
  source = "../../modules/github_identity"

  project_id           = var.project_id
  environment          = var.environment
  resource_prefix      = var.resource_prefix
  github_repository    = var.github_repository
  github_repository_id = var.github_repository_id
  state_bucket_name    = "${var.project_id}-proxy-builder-tfstate"
}
