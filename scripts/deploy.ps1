param(
  [string]$Prefix,
  [string]$ProjectName,
  [string]$Region
)

$ErrorActionPreference = 'Stop'

# Fetch parameters and secret
$bucket = (aws ssm get-parameter --region $Region --name "$Prefix/artifacts/bucket" --query 'Parameter.Value' --output text)
$rds    = (aws ssm get-parameter --region $Region --name "$Prefix/db/endpoint" --query 'Parameter.Value' --output text)
$db     = (aws ssm get-parameter --region $Region --name "$Prefix/db/name"     --query 'Parameter.Value' --output text)
$user   = (aws ssm get-parameter --region $Region --name "$Prefix/db/username" --query 'Parameter.Value' --output text)
$pwd    = (aws secretsmanager get-secret-value --region $Region --secret-id "$ProjectName-$Region/db/password" --query 'SecretString' --output text)

# Prepare folders and download artifact
New-Item -ItemType Directory -Force -Path C:\deploy       | Out-Null
New-Item -ItemType Directory -Force -Path C:\inetpub\app  | Out-Null
aws s3 cp "s3://$bucket/latest/" C:\deploy\app\ --recursive

# Set connection string as machine-level env var
$cs = "Server=$rds;Database=$db;User Id=$user;Password=$pwd;TrustServerCertificate=True;"
[Environment]::SetEnvironmentVariable("APP_DB_CONNECTION", $cs, "Machine")

# Configure IIS to serve our app
Import-Module WebAdministration
if (-Not (Test-Path IIS:\AppPools\AppPool)) { New-WebAppPool -Name "AppPool" }
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) { Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue; Remove-Website -Name "Default Web Site" -ErrorAction SilentlyContinue }
if (-Not (Get-Website -Name "AppSite" -ErrorAction SilentlyContinue)) {
  New-Website -Name "AppSite" -Port 80 -PhysicalPath "C:\inetpub\app" -ApplicationPool "AppPool"
} else {
  Set-ItemProperty "IIS:\Sites\AppSite" -Name physicalPath -Value "C:\inetpub\app"
}

# Deploy files and restart
Copy-Item -Path C:\deploy\app\* -Destination C:\inetpub\app -Recurse -Force
Restart-WebAppPool -Name "AppPool"
Restart-Service W3SVC

Write-Host "Deployment complete."

