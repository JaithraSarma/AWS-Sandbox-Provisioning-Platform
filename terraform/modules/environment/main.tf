data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment_name}"

  common_tags = {
    Name                      = local.name_prefix
    Project                   = var.project_name
    ManagedBy                 = "terraform"
    "provisioner/project"     = var.project_name
    "provisioner/environment" = var.environment_name
    owner                     = var.owner
    "created-at"              = var.created_at
    "ttl-hours"               = tostring(var.ttl_hours)
    "allowed-ssh-cidr"        = var.allowed_ssh_cidr
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.42.1.0/24"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance" {
  name_prefix = "${local.name_prefix}-"
  description = "SSH access for ${var.environment_name}"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = var.key_name == "" ? null : var.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2"
  })
}

resource "aws_ssm_parameter" "environment_metadata" {
  overwrite = true
  name      = "/jaith/aws-env-provisioner/environments/${var.environment_name}"
  type      = "String"
  value = jsonencode({
    environment_name = var.environment_name
    owner            = var.owner
    created_at       = var.created_at
    ttl_hours        = var.ttl_hours
    state_bucket     = var.state_bucket_name
    state_key        = var.state_key
    instance_id      = aws_instance.this.id
  })

  tags = local.common_tags
}
