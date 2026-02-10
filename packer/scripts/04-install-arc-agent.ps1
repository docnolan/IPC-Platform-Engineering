# 04-install-arc-agent.ps1
# Purpose: Pre-stage Azure Arc Connected Machine Agent

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 4: Installing Azure Arc Agent ===" -ForegroundColor Cyan

# Download Azure Connected Machine Agent
$downloadUrl = "https://aka.ms/AzureConnectedMachineAgent"
$installerPath = "$env:TEMP\AzureConnectedMachineAgent.msi"

Write-Host "Downloading Azure Connected Machine Agent..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# Install the agent
Write-Host "Installing agent..." -ForegroundColor Yellow
$installArgs = "/i `"$installerPath`" /qn /norestart"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Azure Connected Machine Agent installation failed with exit code: $($process.ExitCode)"
}

# Create registration script template for post-deployment
$registrationScript = @'
# Azure Arc Registration Script
# Run this script on first boot after deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [string]$ServicePrincipalId,
    [string]$ServicePrincipalSecret,
    [string]$CustomerName = "DMC-Customer"
)

$hostname = $env:COMPUTERNAME

& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id $ServicePrincipalId `
    --service-principal-secret $ServicePrincipalSecret `
    --resource-group $ResourceGroup `
    --tenant-id $TenantId `
    --location $Location `
    --subscription-id $SubscriptionId `
    --cloud "AzureCloud" `
    --tags "Environment=Production,Platform=IPC,Customer=$CustomerName,Hostname=$hostname"
'@

$registrationScript | Out-File -FilePath "C:\ProgramData\IPCPlatform\Scripts\Register-AzureArc.ps1" -Encoding UTF8

# Clean up
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Host "=== Stage 4 Complete ===" -ForegroundColor Green
Write-Host "Arc agent installed. Registration script: C:\ProgramData\IPCPlatform\Scripts\Register-AzureArc.ps1" -ForegroundColor Cyan
