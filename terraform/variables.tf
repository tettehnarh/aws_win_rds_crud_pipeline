variable "aws_region" { default = "us-east-1" }
variable "project_name" { default = "aws-win-rds-crud" }
variable "domain_name" { default = "leslienarh.com" }
variable "app_subdomain" { default = "app" }

# Instance sizes
variable "ec2_instance_type" { default = "t3.medium" }

# RDS
variable "db_engine_version" { default = "15.00" } # SQL Server 2019 family (example)
variable "db_instance_class" { default = "db.t3.micro" }
variable "db_name" { default = "AppDb" }
variable "db_username" { default = "sqlserveradmin" }

# Budget
variable "monthly_budget" { default = 25 }
variable "budget_email" { default = "codewithleslie@gmail.com" }

