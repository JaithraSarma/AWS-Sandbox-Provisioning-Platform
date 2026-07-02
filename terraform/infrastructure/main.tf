data "aws_caller_identity" "current" {}

data "terraform_remote_state" "backend" {
  backend = "local"

  config = {
    path = "${path.module}/../backend/terraform.tfstate"
  }
}

locals {
  aws_region        = data.terraform_remote_state.backend.outputs.aws_region
  state_bucket_name = data.terraform_remote_state.backend.outputs.state_bucket_name
  lock_table_name   = data.terraform_remote_state.backend.outputs.lock_table_name

  codebuild_project_name = "${var.project_name}-terraform"
  provision_lambda_name  = "${var.project_name}-provision-api"
  cleanup_lambda_name    = "${var.project_name}-cleanup"

  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

data "archive_file" "provision_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/provision"
  output_path = "${path.root}/.terraform/${local.provision_lambda_name}.zip"
}

data "archive_file" "cleanup_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/cleanup"
  output_path = "${path.root}/.terraform/${local.cleanup_lambda_name}.zip"
}

resource "aws_sns_topic" "warnings" {
  name = "${var.project_name}-teardown-warnings"
  tags = merge(local.common_tags, { Component = "notifications" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.warnings.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.codebuild_project_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "provision_lambda" {
  name              = "/aws/lambda/${local.provision_lambda_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "cleanup_lambda" {
  name              = "/aws/lambda/${local.cleanup_lambda_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_iam_role" "codebuild" {
  name = "${local.codebuild_project_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Component = "codebuild" })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.codebuild_project_name}-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteBuildLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      },
      {
        Sid      = "ListTerraformStatePrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.state_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["${var.state_key_prefix}/*"]
          }
        }
      },
      {
        Sid    = "ManageTerraformStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${local.state_bucket_name}/${var.state_key_prefix}/*"
      },
      {
        Sid    = "ManageTerraformLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${local.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.lock_table_name}"
      },
      {
        Sid    = "ReadEc2ForTerraform"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageProvisionedEc2Environment"
        Effect = "Allow"
        Action = [
          "ec2:AssociateRouteTable",
          "ec2:AttachInternetGateway",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateInternetGateway",
          "ec2:CreateRoute",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:CreateTags",
          "ec2:CreateVpc",
          "ec2:DeleteInternetGateway",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSubnet",
          "ec2:DeleteTags",
          "ec2:DeleteVpc",
          "ec2:DetachInternetGateway",
          "ec2:DisassociateRouteTable",
          "ec2:ModifySubnetAttribute",
          "ec2:ModifyVpcAttribute",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageEnvironmentParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:ListTagsForResource",
          "ssm:RemoveTagsFromResource"
        ]
        Resource = [
          "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/environments/*",
          "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/warnings/*",
          "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/teardown-requests/*"
        ]
      },
      {
        Sid    = "DescribeSSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "terraform" {
  name          = local.codebuild_project_name
  description   = "Runs Terraform provision and destroy for ${var.project_name} environments."
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_REGION"
      value = local.aws_region
    }

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = local.state_bucket_name
    }

    environment_variable {
      name  = "TF_LOCK_TABLE"
      value = local.lock_table_name
    }

    environment_variable {
      name  = "TF_STATE_PREFIX"
      value = var.state_key_prefix
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
      status     = "ENABLED"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.repository_url
    git_clone_depth = 1
    buildspec       = "buildspec.yml"
  }

  source_version = var.source_version

  tags = merge(local.common_tags, { Component = "codebuild" })
}

resource "aws_iam_role" "provision_lambda" {
  name = "${local.provision_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Component = "api" })
}

resource "aws_iam_role_policy" "provision_lambda" {
  name = "${local.provision_lambda_name}-policy"
  role = aws_iam_role.provision_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.provision_lambda.arn}:*"
      },
      {
        Sid      = "StartProvisionBuild"
        Effect   = "Allow"
        Action   = "codebuild:StartBuild"
        Resource = aws_codebuild_project.terraform.arn
      },
      {
        Sid    = "WriteEnvironmentMetadata"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/environments/*"
      }
    ]
  })
}

resource "aws_lambda_function" "provision" {
  function_name    = local.provision_lambda_name
  role             = aws_iam_role.provision_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.provision_lambda.output_path
  source_code_hash = data.archive_file.provision_lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      CODEBUILD_PROJECT_NAME = aws_codebuild_project.terraform.name
      DEFAULT_ALLOWED_CIDR   = var.default_allowed_ssh_cidr
      PROJECT_NAME           = var.project_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.provision_lambda]
  tags       = merge(local.common_tags, { Component = "api" })
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = merge(local.common_tags, { Component = "api" })
}

resource "aws_apigatewayv2_integration" "provision" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.provision.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "provision" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /environments"
  target    = "integrations/${aws_apigatewayv2_integration.provision.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  tags = merge(local.common_tags, { Component = "api" })
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.provision.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_iam_role" "cleanup_lambda" {
  name = "${local.cleanup_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Component = "cleanup" })
}

resource "aws_iam_role_policy" "cleanup_lambda" {
  name = "${local.cleanup_lambda_name}-policy"
  role = aws_iam_role.cleanup_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cleanup_lambda.arn}:*"
      },
      {
        Sid    = "ReadTaggedEc2Resources"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid      = "StartDestroyBuild"
        Effect   = "Allow"
        Action   = "codebuild:StartBuild"
        Resource = aws_codebuild_project.terraform.arn
      },
      {
        Sid      = "PublishWarnings"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.warnings.arn
      },
      {
        Sid    = "TrackWarningsAndTeardowns"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/warnings/*",
          "arn:aws:ssm:${local.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/env/${var.project_name}/teardown-requests/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "cleanup" {
  function_name    = local.cleanup_lambda_name
  role             = aws_iam_role.cleanup_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.cleanup_lambda.output_path
  source_code_hash = data.archive_file.cleanup_lambda.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      CODEBUILD_PROJECT_NAME    = aws_codebuild_project.terraform.name
      DEFAULT_ALLOWED_CIDR      = var.default_allowed_ssh_cidr
      NOTIFICATION_LEAD_MINUTES = tostring(var.notification_lead_minutes)
      PROJECT_NAME              = var.project_name
      SNS_TOPIC_ARN             = aws_sns_topic.warnings.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.cleanup_lambda]
  tags       = merge(local.common_tags, { Component = "cleanup" })
}

resource "aws_cloudwatch_event_rule" "cleanup_schedule" {
  name                = "${var.project_name}-cleanup-schedule"
  description         = "Runs ${var.project_name} TTL cleanup."
  schedule_expression = var.schedule_expression
  tags                = merge(local.common_tags, { Component = "cleanup" })
}

resource "aws_cloudwatch_event_target" "cleanup_lambda" {
  rule      = aws_cloudwatch_event_rule.cleanup_schedule.name
  target_id = local.cleanup_lambda_name
  arn       = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup_schedule.arn
}

