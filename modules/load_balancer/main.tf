
# ------------------------------------------------------------
# Network Load Balancer
# ------------------------------------------------------------
resource "aws_lb" "lb" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.vpc.private_subnets

  enable_deletion_protection = false
  tags = {
    Terraform = "true"
  }
}

resource "aws_alb_target_group" "lb_tg" {
  name        = "${var.name_prefix}-lb-tg"
  port        = var.target_port
  protocol    = "TCP"
  vpc_id      = var.vpc.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
  }

  tags = {
    Terraform = "true"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.lb.id
  port              = 80
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_alb_target_group.lb_tg.id
    type             = "forward"
  }
}