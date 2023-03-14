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
  enable_dns_hostnames                    = true
  enable_dns_support                      = true

  enable_nat_gateway                      = true
  create_database_subnet_group            = true

  tags = {
    Terraform = "true"
  }
}

module "acm" {
  source = "./modules/acm"
}

module "ecs" {
  source = "./modules/ecs"
  
  name_prefix = local.name_prefix
  vpc_id = module.vpc.vpc_id
}

module "load_balancer" {
  source = "./modules/load_balancer"

  name_prefix = local.name_prefix
  vpc = module.vpc
  target_port = var.weatherapi_container_port
}

module "routes" {
  source = "./modules/routes"

  aws_acm_certificate = module.acm.aws_acm_certificate
  domain_name = module.api_gateway.aws_api_gateway_domain_name
  regional_domain_name = module.api_gateway.aws_api_gateway_regional_domain_name
}

module "api_gateway" {
  source = "./modules/api_gateway"

  name_prefix = local.name_prefix
  aws_lb = module.load_balancer.lb
  aws_acm_certificate = module.acm.aws_acm_certificate
  api_gateway_domain_name = var.api_gateway_domain_name
}

module "rds" {
  source = "./modules/rds"

  vpc_id = module.vpc.vpc_id
  database_subnet_group_name = module.vpc.database_subnet_group_name
  name_prefix = local.name_prefix
  database_username = var.database_username
  database_password = var.database_password
}

module "services_weather_api" {
  source = "./modules/services/weather_api"

  name_prefix = local.name_prefix
  vpc_id = module.vpc.vpc_id
  aws_region = var.aws_region
  private_subnets = module.vpc.private_subnets
  ecs_tasks_sg_id = module.ecs.ecs_tasks_sg_id
  db_access_sg_id = module.rds.db_access_sg_id
  aws_ecs_cluster_id = module.ecs.aws_ecs_cluster_id
  weatherapi_host_port = var.weatherapi_host_port
  weatherapi_container_port = var.weatherapi_container_port
  ecs_task_execution_role_arn = module.ecs.ecs_task_execution_role_arn
  aws_alb_target_group_arn = module.load_balancer.aws_alb_target_group.arn
  connection_string = "server=${module.rds.aws_db_address};port=${module.rds.aws_db_port};uid=${var.database_username};pwd=${var.database_password};database=weather_api;sslmode=required"
}

output "api_gateway_endpoint" {
  value = "https://${module.api_gateway.aws_api_gateway_domain_name}"
}

output "db_endpoint" {
  value = "${module.rds.aws_db_endpoint}"
}
