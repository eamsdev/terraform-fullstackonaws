terraform {
  backend "s3" {}
}

locals {
  name_prefix = "eamsdev-${var.stack_identifier}-${var.environment}"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                                    = "${local.name_prefix}-vpc"
  cidr                                    = var.aws_main_vpc_cidr

  azs                                     = var.aws_availability_zones
  private_subnets                         = var.public_subnets
  public_subnets                          = var.private_subnets
  database_subnets                        = var.database_subnets
  create_database_internet_gateway_route  = var.public_db
  create_database_subnet_route_table      = var.public_db
  enable_dns_hostnames                    = true
  enable_dns_support                      = true

  enable_nat_gateway                      = true
  create_database_subnet_group            = true

  tags = {
    Terraform = "true"
  }
}

module "api_certificate" {
  source = "./modules/acm"

  domain = var.acm_domain_name
}

module "ecs" {
  source = "./modules/ecs"
  
  name_prefix = local.name_prefix
  vpc_id = module.vpc.vpc_id
}

module "alb_security_group" {
  source  = "terraform-aws-modules/security-group/aws"

  name        = "alb-sg"
  description = "ALB for example usage"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  egress_rules = ["all-all"]
}


module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  internal = true
  name = "alb-test"
  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  security_groups = [module.alb_security_group.security_group_id]
  subnets         = module.vpc.private_subnets

  target_groups = [
    {
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
      health_check = {
        path = "/health"
      }
    }
  ]

  
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
    }
  ]
}


module "api_gateway" {
  source = "terraform-aws-modules/apigateway-v2/aws"

  name          = "dev-http"
  description   = "My awesome HTTP API Gateway"
  protocol_type = "HTTP"

  cors_configuration = {
    allow_headers = ["*"]
    allow_methods = ["*"]
    allow_origins = ["*"]
  }

  # Custom domain
  domain_name                 = var.api_endpoint
  domain_name_certificate_arn = module.acm.aws_acm_certificate.arn  

  # Routes and integrations
  integrations = {
    "ANY /{proxy+}" = {
      connection_type    = "VPC_LINK"
      vpc_link           = "my-vpc"
      integration_type   = "HTTP_PROXY"
      integration_method = "ANY"
      integration_uri    = module.alb.http_tcp_listener_arns[0]
    }
  }

  vpc_links = {
    my-vpc = {
      name               = "example_link"
      security_group_ids = [module.api_gateway_security_group.security_group_id]
      subnet_ids         = module.vpc.private_subnets
    }
  }

  tags = {
    Name = "http-apigateway"
  }
}

module "api_gateway_security_group" {
  source  = "terraform-aws-modules/security-group/aws"

  name        = "api-gateway-sg"
  description = "API Gateway group for example usage"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  egress_rules = ["all-all"]
}

module "routes" {
  source = "./modules/routes"

  aws_acm_certificate = module.acm.aws_acm_certificate
  custom_domain_name = var.api_endpoint
  target_domain_name = module.api_gateway.apigatewayv2_domain_name_target_domain_name
}

module "rds" {
  source = "./modules/rds"

  vpc_id = module.vpc.vpc_id
  public_db = var.public_db
  name_prefix = local.name_prefix
  database_username = var.database_username
  database_password = var.database_password
  database_subnet_group_name = module.vpc.database_subnet_group_name
}

module "services_weather_api" {
  source = "./modules/services/weather_api"

  aws_region = var.aws_region
  private_subnets = module.vpc.private_subnets
  ecs_tasks_sg_id = module.ecs.ecs_tasks_sg_id
  db_access_sg_id = module.rds.db_access_sg_id
  aws_ecs_cluster_id = module.ecs.aws_ecs_cluster_id
  ecs_task_execution_role_arn = module.ecs.ecs_task_execution_role_arn
  aws_alb_target_group_arn = module.alb.target_group_arns[0]
  connection_string = "server=${module.rds.aws_db_address};port=${module.rds.aws_db_port};uid=${var.database_username};pwd=${var.database_password};database=weather_api;sslmode=required"
}

module "cloudfront" {
  source = "./modules/cloudfront"

  api_endpoint = module.api_gateway.apigatewayv2_domain_name_target_domain_name
  certificate_domain_name = var.acm_domain_name
  static_hosting_endpoint = var.static_hosting_endpoint
}

output "cloudfront_endpoint" {
  value = "${var.static_hosting_endpoint}"
}

output "api_endpoint" {
  value = "${var.api_endpoint}"
}

output "db_endpoint" {
  value = "${module.rds.aws_db_endpoint}"
}