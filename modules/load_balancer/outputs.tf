output "lb" {
  value = aws_lb.lb
}

output "aws_alb_target_group" {
  value = aws_alb_target_group.lb_tg
}