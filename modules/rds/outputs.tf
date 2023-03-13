output "aws_db_endpoint" {
  value = aws_db_instance.rds.endpoint
}

output "aws_db_port" {
  value = aws_db_instance.rds.port
}

output "aws_db_address" {
  value = aws_db_instance.rds.address
}

output "db_access_sg_id" {
  value = aws_security_group.db_access_sg.id
}