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

  // allows traffic from the SG itself
  ingress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      self = true
  }

  //allow traffic for TCP 5432
  ingress {
      from_port = 3306
      to_port   = 3306
      protocol  = "tcp"
      security_groups = ["${aws_security_group.db_access_sg.id}"]
  }

  // outbound internet access
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
}