output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.api_gateway.domain_name
}
