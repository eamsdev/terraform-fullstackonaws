# ------------------------------------------------------------
# S3
# ------------------------------------------------------------
resource "aws_s3_bucket" "origin" {
  bucket        = "eamsdev-application-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "origin_avl" {
  bucket = aws_s3_bucket.origin.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "origin_versioning" {
  bucket = aws_s3_bucket.origin.id

  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_block_public" {
  bucket = aws_s3_bucket.origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_identity" "storage" {
  comment = "Identity for S3 eamsdev-application-bucket bucket."
}

data "aws_iam_policy_document" "read_only_access" {
  statement {
    principals {
      identifiers = [aws_cloudfront_origin_access_identity.storage.iam_arn]
      type        = "AWS"
    }
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.origin.bucket}/*"]
  }
}

resource "aws_s3_bucket_policy" "read_only" {
  bucket = aws_s3_bucket.origin.bucket
  policy = data.aws_iam_policy_document.read_only_access.json
}

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
  default_root_object = "index.html"
  aliases = [var.static_hosting_endpoint]
  
  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  } 

  origin {
    domain_name = "${var.api_endpoint}"
    origin_id = "application-api"
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.origin.bucket

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.storage.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.origin.bucket
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id  = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "application-api"
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    viewer_protocol_policy = "allow-all"
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
  name    = var.static_hosting_endpoint
  type    = "A"
  
  alias {
    name                   = aws_cloudfront_distribution.api_gateway.domain_name
    zone_id                = aws_cloudfront_distribution.api_gateway.hosted_zone_id
    evaluate_target_health = true
  }
}