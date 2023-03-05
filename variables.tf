# ------------------------------------------------------------
# Network 
# ------------------------------------------------------------
variable "aws_main_vpc_cidr" { default = "10.0.0.0/16" }
variable "aws_availability_zones" { default = ["ap-southeast-2a", "ap-southeast-2b"] }
variable "public_subnets" { default = ["10.0.1.0/24", "10.0.2.0/24"] }
variable "private_subnets" { default = ["10.0.101.0/24", "10.0.102.0/24"] }

# ------------------------------------------------------------
# ECS 
# ------------------------------------------------------------
variable "home_service_container_port" { default = 3000 }
variable "slave_service_container_port" { default = 3001 }
