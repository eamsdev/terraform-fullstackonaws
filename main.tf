terraform {
  backend "s3" {}
}

locals {
  name_prefix = "eamsdev-${var.stack_identifier}-${var.environment}"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.name_prefix}-vpc"
  cidr = var.aws_main_vpc_cidr

  azs                  = var.aws_availability_zones
  private_subnets      = var.public_subnets
  public_subnets       = var.private_subnets
  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true

  tags = {
    Terraform = "true"
  }
}



# ------------------------------------------------------------
# ECS Apps
# ------------------------------------------------------------
resource "aws_cloudwatch_log_group" "weatherapi_log_group" {
  name = "/ecs/${local.name_prefix}-weatherapi-service"
}

resource "aws_ecs_task_definition" "weatherapi_task_definition" {
  family = "weatherapi-task-family"

  container_definitions = <<EOF
  [
    {
      "name": "${local.name_prefix}-weatherapi-container",
      "image": "docker.io/newdevpleaseignore/weatherapi:latest",
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "${var.aws_region}",
          "awslogs-group": "/ecs/${local.name_prefix}-weatherapi-service",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "portMappings": [
        {
          "containerPort": ${var.weatherapi_container_port},
          "hostPort": ${var.weatherapi_host_port}
        }
      ]
    }
  ]
  EOF

  execution_role_arn = module.ecs.ecs_task_execution_role_arn
  task_role_arn      = module.ecs.ecs_task_execution_role_arn

  # These are the minimum values for Fargate containers.
  cpu                      = 256
  memory                   = 512
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"

  tags = {
    Terraform = "true"
  }
}

resource "aws_ecs_service" "weatherapi_service" {
  name            = "${local.name_prefix}-weatherapi-service"
  task_definition = aws_ecs_task_definition.weatherapi_task_definition.arn
  cluster         = module.ecs.aws_ecs_cluster_id 
  launch_type     = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = module.load_balancer.aws_alb_target_group.arn
    container_name   = "${local.name_prefix}-weatherapi-container"
    container_port   = var.weatherapi_container_port
  }

  network_configuration {
    security_groups  = [module.ecs.ecs_tasks_sg_id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  tags = {
    Terraform = "true"
  }
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

module "api_gateway" {
  source = "./modules/api_gateway"

  name_prefix = local.name_prefix
  aws_lb = module.load_balancer.lb
  aws_acm_certificate = module.acm.aws_acm_certificate
  api_gateway_domain_name = var.api_gateway_domain_name
}

module "acm" {
  source = "./modules/acm"
}

module "routes" {
  source = "./modules/routes"

  aws_acm_certificate = module.acm.aws_acm_certificate
  domain_name = module.api_gateway.aws_api_gateway_domain_name
  regional_domain_name = module.api_gateway.aws_api_gateway_regional_domain_name
}

output "api_gateway_endpoint" {
  value = "https://${module.api_gateway.aws_api_gateway_domain_name}"
}