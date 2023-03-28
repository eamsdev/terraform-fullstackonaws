# ------------------------------------------------------------
# Route 53 Records
# ------------------------------------------------------------

data "aws_route53_zone" "main" {
  name = var.route53_name
}

resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.custom_domain_name
  type    = "CNAME"
  records = [var.target_domain_name]
  ttl     = "60"
}