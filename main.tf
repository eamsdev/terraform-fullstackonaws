terraform {
  backend "s3" {}
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "main-vpc"
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
  name   = "alb-sg"
  vpc_id = module.vpc.vpc_id

  // TODO: Change these ingress to be from whitelisted sources for production
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
  name   = "ecs-task-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"] # Change to ALB security group
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
  name = "ecs-cluster"
}

# ------------------------------------------------------------
# ECS Tasks Permissions
# ------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-task-execution-role"
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
  name = "/ecs/weatherapi-service"
}

resource "aws_ecs_task_definition" "weatherapi_task_definition" {
  family = "weatherapi-task-family"

  container_definitions = <<EOF
  [
    {
      "name": "weatherapi-container",
      "image": "docker.io/newdevpleaseignore/weatherapi:latest",
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "ap-southeast-2",
          "awslogs-group": "/ecs/weatherapi-service",
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

# ------------------------------------------------------------
# ECS Service
# ------------------------------------------------------------
resource "aws_ecs_service" "weatherapi_service" {
  name            = "weatherapi-service"
  task_definition = aws_ecs_task_definition.weatherapi_task_definition.arn
  cluster         = aws_ecs_cluster.main.id
  launch_type     = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = aws_alb_target_group.main.arn
    container_name   = "weatherapi-container"
    container_port   = var.weatherapi_container_port
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = true
  }

  tags = {
    Terraform = "true"
  }
}

# ------------------------------------------------------------
# Application Load Balancer
# Notes:
#     - ALB stays in the public subnet to service incoming network requests
# ------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
  tags = {
    Terraform = "true"
  }
}

resource "aws_alb_target_group" "main" {
  name        = "tg"
  port        = var.weatherapi_container_port
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }

  tags = {
    Terraform = "true"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.main.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.main.id
    type             = "forward"
  }
}