output "aws_db_endpoint" {
  value = aws_db_instance.rds.endpoint
}

output "db_access_sg_id" {
  value = aws_security_group.db_access_sg.id
}