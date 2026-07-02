variable "aws_region" {
  description = "AWS region to deploy the environment into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for tags and SSM paths."
  type        = string
  default     = "aws-env-provisioner"
}

variable "environment_name" {
  description = "Unique environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,38}[a-zA-Z0-9]$", var.environment_name))
    error_message = "Use 3-40 alphanumeric/hyphen characters; do not start or end with a hyphen."
  }
}

variable "owner" {
  description = "Owner username, normally github.actor."
  type        = string
}

variable "created_at" {
  description = "UTC creation timestamp in RFC3339 form."
  type        = string
}

variable "ttl_hours" {
  description = "Environment TTL in hours."
  type        = number

  validation {
    condition     = contains([2, 4, 8, 24], var.ttl_hours)
    error_message = "ttl_hours must be one of 2, 4, 8, or 24."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach SSH on the EC2 instance."
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "Free-tier instance type."
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "Remote state bucket name, recorded in SSM metadata for cleanup workflows."
  type        = string
}

variable "state_key" {
  description = "Remote state key for this environment."
  type        = string
}
