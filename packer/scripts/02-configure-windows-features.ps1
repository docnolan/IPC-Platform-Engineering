# 02-configure-windows-features.ps1
# Purpose: Enable Windows features required for containers and virtualization

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 2: Configuring Windows Features ===" -ForegroundColor Cyan

# Features required for AKS Edge Essentials
$features = @(
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Tools-All",
    "Containers"
)

foreach ($feature in $features) {
    Write-Host "Enabling feature: $feature" -ForegroundColor Yellow
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue
    if ($result.RestartNeeded) {
        Write-Host "  Feature $feature requires restart" -ForegroundColor Gray
    }
}

# Configure Windows Defender exclusions for containers
Write-Host "Configuring Windows Defender exclusions..." -ForegroundColor Yellow
$exclusionPaths = @(
    "C:\ProgramData\AksEdge",
    "C:\Program Files\AksEdge",
    "C:\k",
    "C:\var\log"
)

foreach ($path in $exclusionPaths) {
    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
}

# Disable unnecessary services for OT environments
Write-Host "Disabling unnecessary services..." -ForegroundColor Yellow
$servicesToDisable = @(
    "DiagTrack",          # Diagnostics Tracking
    "dmwappushservice",   # WAP Push
    "MapsBroker",         # Downloaded Maps
    "lfsvc",              # Geolocation
    "WMPNetworkSvc"       # Windows Media Network
)

foreach ($service in $servicesToDisable) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  Disabling: $service" -ForegroundColor Gray
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# Configure power settings (prevent sleep)
Write-Host "Configuring power settings..." -ForegroundColor Yellow
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0

Write-Host "=== Stage 2 Complete ===" -ForegroundColor Green
