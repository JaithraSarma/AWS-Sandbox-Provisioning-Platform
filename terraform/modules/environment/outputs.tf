output "environment_name" {
  value = var.environment_name
}

output "instance_id" {
  value = aws_instance.this.id
}

output "instance_public_ip" {
  value = aws_instance.this.public_ip
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "metadata_parameter_name" {
  value = aws_ssm_parameter.environment_metadata.name
}

