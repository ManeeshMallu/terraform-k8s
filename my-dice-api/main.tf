terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~>5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

#package the lambda source code into a zip archive
data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "dice_api_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

#Attach basic logging privileges to the execution role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Define the lambda function
resource "aws_lambda_function" "dice_lambda" {
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name = "DiceRollHandler"
  role = aws_iam_role.lambda_role.arn
  handler = "dice.handler"
  runtime = "python3.12"
}

# define the HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name = "Dice roll API (Terraform)"
  protocol_type = "HTTP"
}

# Create a default stage for the API
resource "aws_apigatewayv2_stage" "default"{
  api_id = aws_apigatewayv2_api.http_api.id
  name = "$default"
  auto_deploy = true
}

# connect lambda to the API gateway route
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.dice_lambda.invoke_arn
}

resource "aws_apigatewayv2_route" "roll_route" {
  api_id = aws_apigatewayv2_api.http_api.id
  route_key = "GET /roll"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Explicitly allow API gateway to invoke your lambda
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id = "AllowExecutionFromAPIGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dice_lambda.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "lambda_log" {
  name = "/aws/lambda/DiceRollHandler"
  retention_in_days = 7
}
