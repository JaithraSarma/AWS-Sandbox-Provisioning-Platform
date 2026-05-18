output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "provision_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/environments"
}

output "codebuild_project_name" {
  value = aws_codebuild_project.terraform.name
}

output "provision_lambda_name" {
  value = aws_lambda_function.provision.function_name
}

output "cleanup_lambda_name" {
  value = aws_lambda_function.cleanup.function_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.warnings.arn
}

