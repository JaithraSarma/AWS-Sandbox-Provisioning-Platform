variable "aws_region" {
  description = "AWS region for the backend resources."
  type        = string
}

variable "project_name" {
  description = "Project prefix used for names and tags."
  type        = string
  default     = "aws-env-provisioner"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform remote state."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "aws-env-provisioner-tf-locks"
}

