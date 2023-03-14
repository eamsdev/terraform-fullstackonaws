# ------------------------------------------------------------
# RDS
# ------------------------------------------------------------

resource "aws_security_group" "db_access_sg" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.name_prefix}-db-access-sg"
  description = "Allow access to RDS"
}

resource "aws_security_group" "rds_sg" {
  name = "${var.name_prefix}-rds-sg"
  description = "${var.name_prefix} Security Group"
  vpc_id = "${var.vpc_id}"

  // outbound internet access
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "db_public_access_any_rule" {
  security_group_id = aws_security_group.rds_sg.id
  count = var.public_db ? 1 : 0
  type  = "ingress"
  from_port = 0
  to_port = 0
  cidr_blocks = ["0.0.0.0/0"]
  protocol = -1
}

resource "aws_security_group_rule" "db_private_access_self_rule" {
  security_group_id = aws_security_group.rds_sg.id
  type  = "ingress"
  from_port = 0
  to_port = 0
  self = true
  protocol = -1
}

resource "aws_security_group_rule" "db_private_access_sg_rule" {
  security_group_id = aws_security_group.rds_sg.id
  type  = "ingress"
  from_port = 3306
  to_port = 3306
  protocol = "tcp"
  source_security_group_id = aws_security_group.db_access_sg.id
}

resource "aws_db_instance" "rds" {
  identifier             = "${var.name_prefix}-database"
  allocated_storage      = "10"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t3.micro"
  multi_az               = false
  db_name                = "apimysql"
  username               = "${var.database_username}"
  password               = "${var.database_password}"
  db_subnet_group_name   = "${var.database_subnet_group_name}"
  vpc_security_group_ids = ["${aws_security_group.rds_sg.id}"]
  skip_final_snapshot    = true
  publicly_accessible    = var.public_db 
}