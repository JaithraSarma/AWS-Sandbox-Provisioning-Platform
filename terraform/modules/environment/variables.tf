variable "project_name" {
  type = string
}

variable "environment_name" {
  type = string
}

variable "owner" {
  type = string
}

variable "created_at" {
  type = string
}

variable "ttl_hours" {
  type = number
}

variable "allowed_ssh_cidr" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type    = string
  default = null
}

variable "state_bucket_name" {
  type = string
}

variable "state_key" {
  type = string
}
