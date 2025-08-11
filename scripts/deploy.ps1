param(
  [string]$Prefix,
  [string]$ProjectName,
  [string]$Region
)

$ErrorActionPreference = 'Stop'

# AWS CLI path
$awsPath = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

Write-Host "Starting deployment with Prefix: $Prefix, ProjectName: $ProjectName, Region: $Region"

# Fetch parameters and secret
Write-Host "Fetching AWS parameters..."
$bucket = (& $awsPath ssm get-parameter --region $Region --name "$Prefix/artifacts/bucket" --query 'Parameter.Value' --output text)
$rds    = (& $awsPath ssm get-parameter --region $Region --name "$Prefix/db/endpoint" --query 'Parameter.Value' --output text)
$db     = (& $awsPath ssm get-parameter --region $Region --name "$Prefix/db/name"     --query 'Parameter.Value' --output text)
$user   = (& $awsPath ssm get-parameter --region $Region --name "$Prefix/db/username" --query 'Parameter.Value' --output text)
$pwd    = (& $awsPath secretsmanager get-secret-value --region $Region --secret-id "$ProjectName-$Region/db/password" --query 'SecretString' --output text)

Write-Host "Retrieved bucket: $bucket, RDS: $rds, DB: $db, User: $user"

# Prepare folders and download artifact
Write-Host "Preparing directories..."
New-Item -ItemType Directory -Force -Path C:\deploy       | Out-Null
New-Item -ItemType Directory -Force -Path C:\inetpub\app  | Out-Null

Write-Host "Downloading application files from S3..."
& $awsPath s3 cp "s3://$bucket/latest/" C:\deploy\app\ --recursive

# Set connection string as machine-level env var
Write-Host "Setting database connection string..."
$cs = "Server=$rds;Database=$db;User Id=$user;Password=$pwd;TrustServerCertificate=True;"
[Environment]::SetEnvironmentVariable("APP_DB_CONNECTION", $cs, "Machine")

# Configure IIS to serve our app
Write-Host "Configuring IIS..."
Import-Module WebAdministration
if (-Not (Test-Path IIS:\AppPools\AppPool)) {
  Write-Host "Creating AppPool..."
  New-WebAppPool -Name "AppPool"
}
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
  Write-Host "Removing Default Web Site..."
  Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
  Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
}
if (-Not (Get-Website -Name "AppSite" -ErrorAction SilentlyContinue)) {
  Write-Host "Creating AppSite..."
  New-Website -Name "AppSite" -Port 80 -PhysicalPath "C:\inetpub\app" -ApplicationPool "AppPool"
} else {
  Write-Host "Updating AppSite path..."
  Set-ItemProperty "IIS:\Sites\AppSite" -Name physicalPath -Value "C:\inetpub\app"
}

# Deploy files and restart
Write-Host "Copying application files..."
Copy-Item -Path C:\deploy\app\* -Destination C:\inetpub\app -Recurse -Force

Write-Host "Restarting IIS..."
Restart-WebAppPool -Name "AppPool"
Restart-Service W3SVC

Write-Host "Deployment complete."

