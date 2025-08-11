# AWS Windows RDS CRUD Pipeline

This project demonstrates a complete AWS deployment pipeline with:

- **Windows Server EC2** running IIS + ASP.NET Core
- **RDS SQL Server Express** for the database
- **Application Load Balancer** with HTTPS (ACM certificate)
- **GitHub Actions CI/CD** with OIDC authentication
- **Systems Manager** for secure deployments
- **Terraform** for infrastructure as code

## Architecture

- ALB → EC2 Windows Server (IIS) → RDS SQL Server
- GitHub Actions builds and deploys via SSM
- Route 53 DNS: app.leslienarh.com
- Budget alerts and cost monitoring

## Deployment

1. `terraform apply` to provision infrastructure
2. Set GitHub secret `AWS_GITHUB_ROLE_ARN`
3. Push to main branch triggers deployment

## App Features

Simple CRUD application for Products (ID, Name, Price) using:
- ASP.NET Core 8 Razor Pages
- Entity Framework Core
- SQL Server provider
- Auto-migrations on startup

## Status

🔧 Currently debugging 500 error - detailed error pages enabled for diagnosis.

Trigger deployment: 2025-01-11 update