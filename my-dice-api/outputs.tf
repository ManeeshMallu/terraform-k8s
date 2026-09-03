output "api_url" {
  value       = "${aws_apigatewayv2_stage.default.invoke_url}roll"
  description = "The live endpoint URL to roll the dice"
}
