output "aws_api_gateway_domain_name" {
  value = aws_api_gateway_domain_name.main.domain_name
}

output "aws_api_gateway_regional_domain_name" {
  value = aws_api_gateway_domain_name.main.regional_domain_name
}