# ------------------------------------------------------------
# AWS Cloudfront
# ------------------------------------------------------------

provider "aws" {
  alias = "virginia"
  region = "us-east-1"
}

data "aws_acm_certificate" "main" {
  domain = var.domain
  provider = aws.virginia
}

data "aws_route53_zone" "main" {
  name = var.route53_name
}

resource "aws_cloudfront_distribution" "api_gateway" {
  enabled = true
  aliases = [var.cloudfront_alternate_domain]
  
  origin {
    domain_name = "${var.aws_api_gateway_domain_name}"
    origin_id = "application-api"
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    # path_pattern     = "api/*" TODO: need to add this for ordered cache behavior when S3 origin is added
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "application-api"
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "https-only"
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.main.arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_route53_record" "cloudfront_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.cloudfront_alternate_domain
  type    = "A"
  ttl     = "300"
  records = [aws_cloudfront_distribution.api_gateway.domain_name]
}