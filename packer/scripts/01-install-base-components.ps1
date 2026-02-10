# 01-install-base-components.ps1
# Purpose: Install foundational components for IPC platform

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "=== Stage 1: Installing Base Components ===" -ForegroundColor Cyan

# Configure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install Chocolatey
Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
$env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"
choco feature enable -n allowGlobalConfirmation

# Install essential packages
$packages = @(
    "powershell-core",
    "azure-cli",
    "git",
    "7zip",
    "notepadplusplus"
)

foreach ($package in $packages) {
    Write-Host "Installing $package..." -ForegroundColor Yellow
    choco install $package -y --no-progress
}

# Install NuGet provider
Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Install PowerShell modules
$modules = @(
    "Az.Accounts",
    "Az.Resources",
    "Az.ConnectedMachine"
)

foreach ($module in $modules) {
    Write-Host "Installing module: $module" -ForegroundColor Yellow
    Install-Module -Name $module -Force -AllowClobber -Scope AllUsers
}

# Create standard directories
$directories = @(
    "C:\ProgramData\IPCPlatform",
    "C:\ProgramData\IPCPlatform\Logs",
    "C:\ProgramData\IPCPlatform\Config",
    "C:\ProgramData\IPCPlatform\Scripts"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Host "=== Stage 1 Complete ===" -ForegroundColor Green
