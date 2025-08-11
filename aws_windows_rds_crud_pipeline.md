# AI Coding Agent Prompt: AWS + Windows Server + RDS SQL Server + CI/CD + Terraform

## Objective
Create a fully functional demonstration environment on AWS that includes:
1. **Windows Server EC2** instance hosting an ASP.NET Core web application (CRUD demo).
2. **Amazon RDS** running SQL Server for the application database.
3. **CI/CD pipeline** for automated build, deploy, and database migrations.
4. **Terraform** scripts to provision infrastructure.

---

## Detailed Requirements

### 1. Infrastructure Provisioning (Terraform)
- Provision a **Windows Server EC2 instance**.
- Install and configure **IIS** to host ASP.NET Core apps.
- Create an **Amazon RDS SQL Server** instance.
- Configure **security groups**:
  - Allow HTTP/HTTPS (80/443) inbound to EC2.
  - Allow SQL Server (1433) from EC2 to RDS.
- Output connection details (RDS endpoint, EC2 public DNS).

### 2. Application Development (ASP.NET Core + EF Core)
- Create a basic **CRUD web app** with the following entity:
  ```csharp
  public class Product
  {
      public int Id { get; set; }
      public string Name { get; set; }
      public decimal Price { get; set; }
  }
  ```
- Use **Entity Framework Core** for database access.
- Configure the app to connect to **RDS SQL Server** using a connection string from environment variables.

### 3. Database Migrations
- Implement EF Core migrations for schema changes.
- **Example**: Adding a `Category` table
  ```bash
  dotnet ef migrations add AddCategoryTable
  dotnet ef database update
  ```
- Migrations should be automatically applied during CI/CD deployment.

### 4. CI/CD Setup (GitHub Actions)
- On code push to `main`:
  1. Build and test the ASP.NET Core app.
  2. Run `dotnet ef database update` to apply migrations to RDS.
  3. Deploy to the Windows Server EC2 instance (via WinRM or SSM).

**Example migration step in workflow:**
```yaml
- name: Run EF Core migrations
  run: dotnet ef database update --connection "$RDS_CONNECTION_STRING"
```

### 5. Connecting to RDS
- Use SQL Server Management Studio (SSMS) locally or on the EC2 instance:
  - **Server**: `<rds-endpoint>,1433`
  - **User**: `admin`
  - **Password**: `<password>`
- Ensure the security group allows traffic from EC2 to RDS.

---

## Deliverables
1. **Terraform scripts** for infra.
2. **ASP.NET Core CRUD app** with EF Core.
3. **GitHub Actions workflow** with migration runner.
4. **Documentation** on connecting to RDS and running migrations.

---

## Goal
Enable a complete, automated demonstration environment where pushing code:
- Updates the app.
- Updates the database schema.
- Requires zero manual intervention.
