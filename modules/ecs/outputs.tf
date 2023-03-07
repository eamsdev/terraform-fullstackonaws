output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "aws_ecs_cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "ecs_tasks_sg_id" {
  value = aws_security_group.ecs_tasks_sg.id
}