locals {
  name_prefix = "${var.project_name}-${var.aws_region}"
  app_fqdn    = "${var.app_subdomain}.${var.domain_name}"
  # SSM Parameter Store top-level path cannot begin with reserved words like 'aws' or 'ssm'
  ssm_prefix = "/app/${var.project_name}-${var.aws_region}"
}

# Random suffix for unique bucket names
resource "random_id" "suffix" {
  byte_length = 3
}

# VPC (new)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = local.name_prefix
  cidr = "10.70.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.70.1.0/24", "10.70.2.0/24"]
  private_subnets = ["10.70.11.0/24", "10.70.12.0/24"]

  enable_nat_gateway = false # keep costs down
  single_nat_gateway = true
}

# Security groups
resource "aws_security_group" "alb_sg" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "EC2 SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "SQL Server from EC2"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM for EC2 (SSM + S3 + Parameter/Secrets read)
resource "aws_iam_role" "ec2_role" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ec2_policy" {
  name   = "${local.name_prefix}-ec2-policy"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ec2_policy.json
}

data "aws_iam_policy_document" "ec2_policy" {
  statement {
    actions = [
      "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParameterHistory", "ssm:DescribeParameters",
      "ssmmessages:*", "ec2messages:*",
      "s3:GetObject", "s3:ListBucket",
      "secretsmanager:GetSecretValue"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Attach managed policy for SSM core
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Artifact bucket
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-${random_id.suffix.hex}-artifacts"
}

# Secrets and parameters
resource "random_password" "db" {
  length  = 20
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${local.name_prefix}/db/password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_prefix}/db/name"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_user" {
  name  = "${local.ssm_prefix}/db/username"
  type  = "String"
  value = var.db_username
}

# RDS subnet group
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-rds-subnet"
  subnet_ids = module.vpc.private_subnets
}

# RDS Instance (SQL Server Express)
resource "aws_db_instance" "sqlserver" {
  identifier             = "${local.name_prefix}-sql-express"
  engine                 = "sqlserver-ex"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  username               = var.db_username
  password               = random_password.db.result
  # db_name not supported for SQL Server; must be null
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false
  multi_az            = false
  port                = 1433
}

# Store RDS endpoint in SSM
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "${local.ssm_prefix}/db/endpoint"
  type  = "String"
  value = aws_db_instance.sqlserver.address
}

# ALB
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"
  health_check {
    path    = "/"
    matcher = "200"
  }
}

# ACM cert for the subdomain
resource "aws_acm_certificate" "cert" {
  domain_name       = local.app_fqdn
  validation_method = "DNS"
}

data "aws_route53_zone" "primary" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Windows AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["801119661308"] # Amazon

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-POWERSHELL
              <powershell>
              $ErrorActionPreference = 'Stop'
              # Enable IIS
              Install-WindowsFeature Web-Server

              # Install .NET Core Hosting Bundle (ASP.NET Core runtime)
              $bundleUrl = "https://download.visualstudio.microsoft.com/download/pr/197f8b44-8dae-4b0a-8a51-2c9ba902eaa6/1d4a3a4f2a937e83d48a11cd2d7f7d87/dotnet-hosting-8.0.5-win.exe"
              Invoke-WebRequest -Uri $bundleUrl -OutFile C:\\Temp\\dotnet-hosting.exe
              Start-Process -FilePath C:\\Temp\\dotnet-hosting.exe -ArgumentList "/quiet" -Wait

              # Install AWS CLI v2
              Invoke-WebRequest -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile C:\\Temp\\AWSCLIV2.msi
              Start-Process msiexec.exe -ArgumentList "/i C:\\Temp\\AWSCLIV2.msi /qn /norestart" -Wait
              $env:Path += ";C:\\Program Files\\Amazon\\AWSCLIV2\\"

              # Place deploy script
              New-Item -ItemType Directory -Force -Path C:\\deploy | Out-Null
              Set-Content -Path C:\\deploy\\deploy.ps1 -Value @"
              param(
                [string]$Prefix,
                [string]$ProjectName,
                [string]$Region
              )
              $ErrorActionPreference = 'Stop'
              $bucket = (aws ssm get-parameter --region $Region --name "$Prefix/artifacts/bucket" --query 'Parameter.Value' --output text)
              $rds    = (aws ssm get-parameter --region $Region --name "$Prefix/db/endpoint" --query 'Parameter.Value' --output text)
              $db     = (aws ssm get-parameter --region $Region --name "$Prefix/db/name"     --query 'Parameter.Value' --output text)
              $user   = (aws ssm get-parameter --region $Region --name "$Prefix/db/username" --query 'Parameter.Value' --output text)
              $pwd    = (aws secretsmanager get-secret-value --region $Region --secret-id "$ProjectName-$Region/db/password" --query 'SecretString' --output text)
              New-Item -ItemType Directory -Force -Path C:\\inetpub\\app  | Out-Null
              aws s3 cp "s3://$bucket/latest/" C:\\deploy\\app\\ --recursive
              $cs = "Server=$rds;Database=$db;User Id=$user;Password=$pwd;TrustServerCertificate=True;"
              [Environment]::SetEnvironmentVariable("APP_DB_CONNECTION", $cs, "Machine")
              Import-Module WebAdministration
              if (-Not (Test-Path IIS:\\AppPools\\AppPool)) { New-WebAppPool -Name "AppPool" }
              if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) { Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue; Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue }
              if (-Not (Get-Website -Name "AppSite" -ErrorAction SilentlyContinue)) {
                New-Website -Name "AppSite" -Port 80 -PhysicalPath "C:\\inetpub\\app" -ApplicationPool "AppPool"
              } else {
                Set-ItemProperty "IIS:\\Sites\\AppSite" -Name physicalPath -Value "C:\\inetpub\\app"
              }
              Copy-Item -Path C:\\deploy\\app\\* -Destination C:\\inetpub\\app -Recurse -Force
              Restart-WebAppPool -Name "AppPool"
              Restart-Service W3SVC
              Write-Host "Deployment complete."
              "@

              </powershell>
              POWERSHELL

  tags = {
    Name = "${local.name_prefix}-web"
  }
}

# Attach EC2 to Target Group
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# Route 53 record for the app
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = local.app_fqdn
  type    = "A"
  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# Store artifact bucket & instance id in SSM for CI/CD
resource "aws_ssm_parameter" "artifact_bucket" {
  name  = "${local.ssm_prefix}/artifacts/bucket"
  type  = "String"
  value = aws_s3_bucket.artifacts.bucket
}

resource "aws_ssm_parameter" "instance_id" {
  name  = "${local.ssm_prefix}/ec2/instance-id"
  type  = "String"
  value = aws_instance.web.id
}

# GitHub OIDC provider and deploy role
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = [
    "sts.amazonaws.com"
  ]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:tettehnarh/aws_win_rds_crud_pipeline:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    actions = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }
  statement {
    actions   = ["ssm:SendCommand", "ssm:GetParameter", "ssm:GetParameters", "ssm:GetCommandInvocation"]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:DescribeInstances", "ssm:ListCommands", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name_prefix}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}

# Budget
resource "aws_budgets_budget" "monthly" {
  name              = "${local.name_prefix}-budget"
  budget_type       = "COST"
  limit_amount      = var.monthly_budget
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-DD_hh:mm", timestamp())

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

output "alb_dns_name" { value = aws_lb.app.dns_name }
output "app_url" { value = "https://${local.app_fqdn}" }
output "rds_endpoint" { value = aws_db_instance.sqlserver.address }
output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }

