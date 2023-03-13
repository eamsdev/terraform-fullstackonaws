
# ------------------------------------------------------------
# ECS Apps
# ------------------------------------------------------------
resource "aws_cloudwatch_log_group" "weatherapi_log_group" {
  name = "/ecs/${var.name_prefix}-weatherapi-service"
}

resource "aws_ecs_task_definition" "weatherapi_task_definition" {
  family = "weatherapi-task-family"

  container_definitions = <<EOF
  [
    {
      "name": "${var.name_prefix}-weatherapi-container",
      "image": "docker.io/newdevpleaseignore/weatherapi:latest",
      "environment": [
        {"name": "ASPNETCORE_ConnectionStrings__dbConnectionString", "value": "${var.connection_string}"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-region": "${var.aws_region}",
          "awslogs-group": "/ecs/${var.name_prefix}-weatherapi-service",
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

  execution_role_arn = var.ecs_task_execution_role_arn
  task_role_arn      = var.ecs_task_execution_role_arn

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
  name            = "${var.name_prefix}-weatherapi-service"
  task_definition = aws_ecs_task_definition.weatherapi_task_definition.arn
  cluster         = var.aws_ecs_cluster_id 
  launch_type     = "FARGATE"

  desired_count = 1

  load_balancer {
    target_group_arn = var.aws_alb_target_group_arn
    container_name   = "${var.name_prefix}-weatherapi-container"
    container_port   = var.weatherapi_container_port
  }

  network_configuration {
    security_groups  = [var.ecs_tasks_sg_id, var.db_access_sg_id]
    subnets          = var.private_subnets
    assign_public_ip = false
  }

  tags = {
    Terraform = "true"
  }
}