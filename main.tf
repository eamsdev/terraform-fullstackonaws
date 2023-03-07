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
# Security Groups - ALB / ECS Tasks
# ------------------------------------------------------------

resource "aws_security_group" "alb_sg" {
  name   = "${local.name_prefix}-alb-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Terraform = "true"
  }
}

resource "aws_security_group" "ecs_tasks_sg" {
  name   = "${local.name_prefix}-ecs-tasks-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"] # Change to local private subnet traffic
    #security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Terraform = "true"
  }
}

# ------------------------------------------------------------
# ECS Cluster
# ------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-ecs-cluster"
}

# ------------------------------------------------------------
# ECS Tasks Permissions
# ------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.name_prefix}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  
  tags = {
    Terraform = "true"
  }
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
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

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_execution_role.arn

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
  cluster         = aws_ecs_cluster.main.id
  launch_type     = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = module.load_balancer.aws_alb_target_group.arn
    container_name   = "${local.name_prefix}-weatherapi-container"
    container_port   = var.weatherapi_container_port
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  tags = {
    Terraform = "true"
  }
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
  aws_api_gateway_domain_name = module.api_gateway.aws_api_gateway_domain_name
}

output "api_gateway_endpoint" {
  value = "https://${module.api_gateway.aws_api_gateway_domain_name.domain_name}"
}