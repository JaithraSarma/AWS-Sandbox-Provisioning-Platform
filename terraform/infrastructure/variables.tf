variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource names, tags, and SSM paths."
  type        = string
  default     = "aws-env-provisioner"
}

variable "state_bucket_name" {
  description = "Terraform remote state bucket."
  type        = string
}

variable "state_key_prefix" {
  description = "Prefix used for per-environment Terraform state keys."
  type        = string
  default     = "envs"
}

variable "lock_table_name" {
  description = "Terraform state lock table."
  type        = string
}

variable "repository_url" {
  description = "Git repository URL CodeBuild clones, for example https://github.com/OWNER/aws-env-provisioner.git."
  type        = string
}

variable "source_version" {
  description = "Branch or ref CodeBuild builds from."
  type        = string
  default     = "main"
}

variable "sns_email" {
  description = "Email address that receives teardown warnings. Leave empty to create the topic without a subscription."
  type        = string
  default     = ""
}

variable "notification_lead_minutes" {
  description = "Minutes before expiration to send SNS warnings."
  type        = number
  default     = 30
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for cleanup scans."
  type        = string
  default     = "rate(2 hours)"
}

variable "default_allowed_ssh_cidr" {
  description = "Default CIDR used when the API request omits allowed_ssh_cidr."
  type        = string
  default     = "0.0.0.0/0"
}

