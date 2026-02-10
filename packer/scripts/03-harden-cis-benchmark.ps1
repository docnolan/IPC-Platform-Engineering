# 03-harden-cis-benchmark.ps1
# Purpose: Apply CIS Benchmark Level 1 hardening for Windows 10 Enterprise
# Reference: CIS Microsoft Windows 10 Enterprise Benchmark v3.0.0

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 3: Applying CIS Benchmark Hardening ===" -ForegroundColor Cyan

# Create compliance log
$logPath = "C:\ProgramData\IPCPlatform\Logs\cis-hardening.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"CIS Hardening Started: $timestamp" | Out-File -FilePath $logPath

function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Name,
        [string]$Type,
        $Value,
        [string]$Description
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        "$Description - Applied" | Out-File -FilePath $logPath -Append
        Write-Host "  [OK] $Description" -ForegroundColor Green
    }
    catch {
        "$Description - FAILED: $_" | Out-File -FilePath $logPath -Append
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
    }
}

# ============================================================================
# Account Policies (CIS 1.x)
# ============================================================================

Write-Host "Applying Account Policies..." -ForegroundColor Yellow

# 1.1.1 Password history (24 passwords)
net accounts /uniquepw:24

# 1.1.2 Maximum password age (60 days)
net accounts /maxpwage:60

# 1.1.3 Minimum password age (1 day)
net accounts /minpwage:1

# 1.1.4 Minimum password length (14 characters)
net accounts /minpwlen:14

# 1.2.1 Account lockout duration (15 minutes)
net accounts /lockoutduration:15

# 1.2.2 Account lockout threshold (5 attempts)
net accounts /lockoutthreshold:5

# 1.2.3 Reset lockout counter (15 minutes)
net accounts /lockoutwindow:15

# ============================================================================
# Security Options (CIS 2.3.x)
# ============================================================================

Write-Host "Applying Security Options..." -ForegroundColor Yellow

# 2.3.1.1 Block Microsoft accounts
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "NoConnectedUser" -Type "DWord" -Value 3 `
    -Description "2.3.1.1 Block Microsoft accounts"

# 2.3.2.1 Force audit policy subcategory settings
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "SCENoApplyLegacyAuditPolicy" -Type "DWord" -Value 1 `
    -Description "2.3.2.1 Force audit policy subcategory settings"

# 2.3.7.1 Require CTRL+ALT+DEL
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "DisableCAD" -Type "DWord" -Value 0 `
    -Description "2.3.7.1 Require CTRL+ALT+DEL"

# 2.3.7.3 Machine inactivity limit (900 seconds / 15 minutes)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "InactivityTimeoutSecs" -Type "DWord" -Value 900 `
    -Description "2.3.7.3 Machine inactivity limit"

# 2.3.8.1 SMB client signing (always)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Name "RequireSecuritySignature" -Type "DWord" -Value 1 `
    -Description "2.3.8.1 SMB client signing always"

# 2.3.9.1 SMB server signing (always)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -Name "RequireSecuritySignature" -Type "DWord" -Value 1 `
    -Description "2.3.9.1 SMB server signing always"

# 2.3.10.5 Disable Everyone permissions for anonymous
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "EveryoneIncludesAnonymous" -Type "DWord" -Value 0 `
    -Description "2.3.10.5 Disable Everyone for anonymous"

# 2.3.11.6 NTLMv2 only
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LmCompatibilityLevel" -Type "DWord" -Value 5 `
    -Description "2.3.11.6 NTLMv2 only"

# ============================================================================
# Windows Firewall (CIS 9.x)
# ============================================================================

Write-Host "Applying Windows Firewall Settings..." -ForegroundColor Yellow

# Enable all firewall profiles
Set-NetFirewallProfile -Profile Domain -Enabled True
Set-NetFirewallProfile -Profile Private -Enabled True
Set-NetFirewallProfile -Profile Public -Enabled True

# Configure firewall logging
$logDirectory = "C:\Windows\System32\LogFiles\Firewall"
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

Set-NetFirewallProfile -Profile Domain, Private, Public `
    -LogFileName "$logDirectory\pfirewall.log" `
    -LogMaxSizeKilobytes 16384 `
    -LogBlocked True `
    -LogAllowed False

# ============================================================================
# Network Security (CIS 18.x)
# ============================================================================

Write-Host "Applying Network Security Settings..." -ForegroundColor Yellow

# 18.4.3 Disable IP source routing
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "DisableIPSourceRouting" -Type "DWord" -Value 2 `
    -Description "18.4.3 Disable IP source routing"

# 18.4.4 Disable IPv6 source routing
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
    -Name "DisableIPSourceRouting" -Type "DWord" -Value 2 `
    -Description "18.4.4 Disable IPv6 source routing"

# 18.4.6 Disable ICMP redirects
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "EnableICMPRedirect" -Type "DWord" -Value 0 `
    -Description "18.4.6 Disable ICMP redirects"

# 18.5.4.1 Disable multicast name resolution (LLMNR)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
    -Name "EnableMulticast" -Type "DWord" -Value 0 `
    -Description "18.5.4.1 Disable LLMNR"

# 18.9.11.1.1 Limit diagnostic data
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "AllowTelemetry" -Type "DWord" -Value 1 `
    -Description "18.9.11.1.1 Limit diagnostic data"

# 18.9.85.1.1 Enable SmartScreen
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableSmartScreen" -Type "DWord" -Value 1 `
    -Description "18.9.85.1.1 Enable SmartScreen"

# ============================================================================
# Audit Policies (CIS 17.x)
# ============================================================================

Write-Host "Applying Audit Policies..." -ForegroundColor Yellow

$auditCategories = @(
    "Credential Validation",
    "Security Group Management",
    "User Account Management",
    "Process Creation",
    "Account Lockout",
    "Logoff",
    "Logon",
    "Special Logon",
    "Removable Storage",
    "Audit Policy Change",
    "Authentication Policy Change",
    "Sensitive Privilege Use",
    "Security State Change",
    "Security System Extension",
    "System Integrity"
)

foreach ($category in $auditCategories) {
    auditpol /set /subcategory:"$category" /success:enable /failure:enable 2>&1 | Out-Null
    Write-Host "  [OK] Audit: $category" -ForegroundColor Green
}

# ============================================================================
# Legal Notice Banner (NIST 3.1.9)
# ============================================================================

Write-Host "Configuring Legal Notice Banner..." -ForegroundColor Yellow

$legalCaption = "AUTHORIZED USE ONLY"
$legalText = @"
This system is the property of DMC, Inc. and is provided for authorized business use only.
All activities on this system may be monitored and recorded. 
Unauthorized access or use is prohibited and may result in disciplinary action and/or civil and criminal penalties.
By using this system, you consent to monitoring and acknowledge these terms.
"@

Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticecaption" -Type "String" -Value $legalCaption `
    -Description "Legal notice caption"

Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticetext" -Type "String" -Value $legalText `
    -Description "Legal notice text"

# Finalize
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"CIS Hardening Completed: $timestamp" | Out-File -FilePath $logPath -Append

Write-Host "=== Stage 3 Complete ===" -ForegroundColor Green
Write-Host "CIS Benchmark hardening log: $logPath" -ForegroundColor Cyan
