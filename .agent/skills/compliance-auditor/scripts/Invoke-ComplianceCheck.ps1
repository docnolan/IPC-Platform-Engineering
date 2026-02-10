<#
.SYNOPSIS
    Validates changes against NIST 800-171 control requirements.

.DESCRIPTION
    Analyzes file changes and maps them to affected NIST control families.
    Checks for common compliance issues in code and configuration.

.PARAMETER ChangedFiles
    Array of file paths that have changed (from git diff).

.PARAMETER ControlFamily
    Specific NIST control family to validate (optional).

.EXAMPLE
    .\Invoke-ComplianceCheck.ps1 -ChangedFiles @("packer/scripts/harden.ps1")

.EXAMPLE
    $files = git diff --name-only HEAD~1
    .\Invoke-ComplianceCheck.ps1 -ChangedFiles $files
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]]$ChangedFiles,
    
    [ValidateSet("3.1", "3.3", "3.4", "3.5", "3.8", "3.11", "3.13", "3.14")]
    [string]$ControlFamily
)

# NIST 800-171 Control Family Mapping
$ControlFamilies = @{
    "3.1"  = @{
        Name = "Access Control"
        Triggers = @("rbac", "role", "permission", "access", "auth", "policy")
        Files = @("**/rbac*.yaml", "**/role*.yaml", "**/policy*.yaml")
    }
    "3.3"  = @{
        Name = "Audit and Accountability"
        Triggers = @("log", "audit", "event", "monitor", "trace")
        Files = @("**/log-forwarder/**", "**/health-monitor/**", "**/*audit*")
    }
    "3.4"  = @{
        Name = "Configuration Management"
        Triggers = @("config", "baseline", "harden", "cis", "setting")
        Files = @("packer/**", "kubernetes/**", "**/configmap*")
    }
    "3.5"  = @{
        Name = "Identification and Authentication"
        Triggers = @("identity", "auth", "credential", "password", "mfa", "token")
        Files = @("**/auth*", "**/identity*", "**/secret*")
    }
    "3.8"  = @{
        Name = "Media Protection"
        Triggers = @("encrypt", "bitlocker", "backup", "storage", "disk")
        Files = @("**/backup*", "**/storage*", "**/encrypt*")
    }
    "3.11" = @{
        Name = "Risk Assessment"
        Triggers = @("scan", "vulnerab", "cve", "patch", "update")
        Files = @("**/scan*", "**/vulnerab*")
    }
    "3.13" = @{
        Name = "System and Communications Protection"
        Triggers = @("tls", "ssl", "certificate", "firewall", "network", "encrypt")
        Files = @("**/network*", "**/firewall*", "**/cert*", "**/tls*")
    }
    "3.14" = @{
        Name = "System and Information Integrity"
        Triggers = @("integrity", "antivirus", "malware", "patch", "flaw")
        Files = @("**/integrity*", "**/defender*")
    }
}

# Common compliance anti-patterns to check
$ComplianceIssues = @(
    @{
        Pattern = "password\s*=\s*[`"']"
        Issue = "Hardcoded password detected"
        Control = "3.5.10"
        Severity = "HIGH"
    }
    @{
        Pattern = "secret\s*=\s*[`"'][^{]"
        Issue = "Hardcoded secret detected"
        Control = "3.5.10"
        Severity = "HIGH"
    }
    @{
        Pattern = "connectionstring\s*=\s*[`"']"
        Issue = "Hardcoded connection string detected"
        Control = "3.5.10"
        Severity = "HIGH"
    }
    @{
        Pattern = "disable.*ssl|ssl.*false|verify.*false"
        Issue = "TLS/SSL verification disabled"
        Control = "3.13.8"
        Severity = "HIGH"
    }
    @{
        Pattern = "0\.0\.0\.0|any\s+any|allow\s+all"
        Issue = "Overly permissive network rule"
        Control = "3.13.1"
        Severity = "MEDIUM"
    }
    @{
        Pattern = "chmod\s+777|permissions.*everyone"
        Issue = "Overly permissive file permissions"
        Control = "3.1.2"
        Severity = "MEDIUM"
    }
)

Write-Host "`nCOMPLIANCE CHECK" -ForegroundColor Cyan
Write-Host "================" -ForegroundColor Cyan
Write-Host "Files to analyze: $($ChangedFiles.Count)`n"

$AffectedFamilies = @{}
$Issues = @()
$Passed = @()

# Analyze each changed file
foreach ($file in $ChangedFiles) {
    Write-Host "Analyzing: $file" -ForegroundColor Yellow
    
    # Determine affected control families
    foreach ($familyId in $ControlFamilies.Keys) {
        $family = $ControlFamilies[$familyId]
        
        # Check file patterns
        foreach ($pattern in $family.Files) {
            if ($file -like $pattern) {
                $AffectedFamilies[$familyId] = $family.Name
            }
        }
        
        # Check content triggers (if file exists)
        if (Test-Path $file) {
            $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
            if ($content) {
                foreach ($trigger in $family.Triggers) {
                    if ($content -match $trigger) {
                        $AffectedFamilies[$familyId] = $family.Name
                    }
                }
                
                # Check for compliance issues
                foreach ($check in $ComplianceIssues) {
                    if ($content -match $check.Pattern) {
                        $Issues += @{
                            File = $file
                            Issue = $check.Issue
                            Control = $check.Control
                            Severity = $check.Severity
                        }
                    }
                }
            }
        }
    }
}

# Report affected control families
Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "AFFECTED CONTROL FAMILIES:" -ForegroundColor White

if ($AffectedFamilies.Count -eq 0) {
    Write-Host "  No compliance-relevant changes detected." -ForegroundColor Green
}
else {
    foreach ($familyId in $AffectedFamilies.Keys | Sort-Object) {
        Write-Host "  $familyId - $($AffectedFamilies[$familyId])" -ForegroundColor Yellow
    }
}

# Report compliance issues
Write-Host "`n----------------------------------------" -ForegroundColor Cyan

if ($Issues.Count -gt 0) {
    Write-Host "COMPLIANCE ISSUES FOUND:" -ForegroundColor Red
    foreach ($issue in $Issues) {
        $color = if ($issue.Severity -eq "HIGH") { "Red" } else { "Yellow" }
        Write-Host "`n  [$($issue.Severity)] $($issue.Issue)" -ForegroundColor $color
        Write-Host "    File: $($issue.File)"
        Write-Host "    Control: $($issue.Control)"
    }
    
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "STATUS: NON-COMPLIANT" -ForegroundColor Red
    Write-Host "Remediation required before merge." -ForegroundColor Red
    return $false
}
else {
    Write-Host "COMPLIANCE ISSUES: None detected" -ForegroundColor Green
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "STATUS: COMPLIANT (automated checks passed)" -ForegroundColor Green
    Write-Host "Manual review still recommended for control families:" -ForegroundColor Yellow
    foreach ($familyId in $AffectedFamilies.Keys | Sort-Object) {
        Write-Host "  - $familyId $($AffectedFamilies[$familyId])"
    }
    return $true
}
