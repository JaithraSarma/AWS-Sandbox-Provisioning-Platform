module "environment" {
  source = "../modules/environment"

  project_name      = var.project_name
  environment_name  = var.environment_name
  owner             = var.owner
  created_at        = var.created_at
  ttl_hours         = var.ttl_hours
  allowed_ssh_cidr  = var.allowed_ssh_cidr
  instance_type     = var.instance_type
  key_name          = var.key_name
  state_bucket_name = var.state_bucket_name
  state_key         = var.state_key
}
