# 06-create-manifest.ps1
# Purpose: Create image manifest for tracking and compliance

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 6: Creating Image Manifest ===" -ForegroundColor Cyan

$manifest = @{
    ImageBuildDate       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    WindowsVersion       = (Get-CimInstance Win32_OperatingSystem).Version
    WindowsBuild         = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    ImageType            = "Windows 10 IoT Enterprise LTSC 2021"
    InstalledComponents  = @(
        "Azure Connected Machine Agent",
        "AKS Edge Essentials (K3s)",
        "PowerShell Core",
        "Azure CLI",
        "Chocolatey Package Manager"
    )
    SecurityHardening    = @{
        Framework = "CIS Benchmark"
        Level     = "Level 1"
        Version   = "v3.0.0"
    }
    ComplianceFrameworks = @(
        "NIST 800-171 Rev 2 (Partial)",
        "CMMC Level 2 (Partial)"
    )
    ManagedBy            = "DMC Platform Engineering"
    SupportContact       = "<support-email>"
}

$manifestPath = "C:\ProgramData\IPCPlatform\Config\image-manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding UTF8

Write-Host "Image manifest created: $manifestPath" -ForegroundColor Cyan
Write-Host "=== Stage 6 Complete ===" -ForegroundColor Green
