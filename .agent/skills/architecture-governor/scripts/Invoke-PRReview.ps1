<#
.SYNOPSIS
    Performs automated PR review checks for IPC Platform changes.

.DESCRIPTION
    Analyzes PR files for common issues, convention violations, and
    security concerns. Produces a review report with findings.

.PARAMETER PRId
    Azure DevOps PR ID to review.

.PARAMETER LocalPath
    Local repository path for file analysis (default: current directory).

.PARAMETER ChangedFiles
    Array of changed file paths (alternative to PRId for local review).

.EXAMPLE
    .\Invoke-PRReview.ps1 -PRId 42

.EXAMPLE
    .\Invoke-PRReview.ps1 -ChangedFiles @("docker/health-monitor/Dockerfile", "kubernetes/workloads/health-monitor/deployment.yaml")
#>

param(
    [Parameter(ParameterSetName = "PR")]
    [int]$PRId,
    
    [Parameter(ParameterSetName = "Local")]
    [string[]]$ChangedFiles,
    
    [string]$LocalPath = "."
)

Write-Host "`nPR REVIEW ANALYSIS" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# Review results
$findings = @{
    Blocking = @()
    Warning = @()
    Info = @()
}

# Get changed files
if ($PRId) {
    Write-Host "Fetching PR #$PRId details..." -ForegroundColor Yellow
    try {
        $prFiles = az repos pr diff --id $PRId --query "[].path" -o tsv 2>$null
        if ($prFiles) {
            $ChangedFiles = $prFiles -split "`n" | Where-Object { $_ }
        }
        else {
            Write-Host "ERROR: Could not fetch PR details." -ForegroundColor Red
            return
        }
    }
    catch {
        Write-Host "ERROR: Azure DevOps CLI failed. Using local git diff." -ForegroundColor Yellow
        $ChangedFiles = git diff --name-only HEAD~1 HEAD 2>$null
    }
}

if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
    Write-Host "No changed files to review." -ForegroundColor Yellow
    return
}

Write-Host "Files to review: $($ChangedFiles.Count)`n"

# ===========================================
# File-by-File Analysis
# ===========================================

foreach ($file in $ChangedFiles) {
    Write-Host "Reviewing: $file" -ForegroundColor Yellow
    
    $fullPath = Join-Path $LocalPath $file
    $exists = Test-Path $fullPath
    
    if (-not $exists) {
        Write-Host "  (File deleted or not found locally)" -ForegroundColor Gray
        continue
    }
    
    $content = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
    $lines = Get-Content $fullPath -ErrorAction SilentlyContinue
    
    # -----------------------------------------
    # Convention Checks
    # -----------------------------------------
    
    # Check file naming (lowercase with hyphens)
    $fileName = Split-Path $file -Leaf
    if ($fileName -cmatch "[A-Z]" -and $file -notmatch "\.md$" -and $file -notmatch "SKILL\.md$") {
        $findings.Warning += @{
            File = $file
            Issue = "File name contains uppercase letters"
            Suggestion = "Use lowercase with hyphens: $($fileName.ToLower())"
        }
    }
    
    # -----------------------------------------
    # Security Checks
    # -----------------------------------------
    
    if ($content) {
        # Hardcoded secrets
        $secretPatterns = @(
            @{ Pattern = "password\s*[:=]\s*[`"'][^`"']+[`"']"; Name = "Hardcoded password" }
            @{ Pattern = "secret\s*[:=]\s*[`"'][^{\$][^`"']*[`"']"; Name = "Hardcoded secret" }
            @{ Pattern = "api[_-]?key\s*[:=]\s*[`"'][^`"']+[`"']"; Name = "Hardcoded API key" }
            @{ Pattern = "connectionstring\s*[:=]\s*[`"'][^`"']+[`"']"; Name = "Hardcoded connection string" }
            @{ Pattern = "[a-zA-Z0-9]{32,}"; Name = "Possible token/key (long alphanumeric)" }
        )
        
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern.Pattern) {
                # Exclude known false positives
                if ($file -match "\.md$" -and $pattern.Name -eq "Possible token/key") { continue }
                if ($content -match "\$\{" -or $content -match "\$env:" -or $content -match "valueFrom:") { continue }
                
                $findings.Blocking += @{
                    File = $file
                    Issue = "$($pattern.Name) detected"
                    Suggestion = "Use environment variables or Kubernetes secrets"
                }
            }
        }
        
        # Insecure configurations
        if ($content -match "verify\s*[:=]\s*false" -or $content -match "ssl\s*[:=]\s*false") {
            $findings.Blocking += @{
                File = $file
                Issue = "TLS/SSL verification disabled"
                Suggestion = "Enable certificate verification for security"
            }
        }
    }
    
    # -----------------------------------------
    # Dockerfile Checks
    # -----------------------------------------
    
    if ($file -match "Dockerfile$") {
        # Check for latest tag
        if ($content -match "FROM\s+\S+:latest") {
            $findings.Warning += @{
                File = $file
                Issue = "Using 'latest' tag in FROM"
                Suggestion = "Pin to specific version for reproducibility"
            }
        }
        
        # Check for root user
        if ($content -notmatch "USER\s+\S+" -and $content -notmatch "USER\s+\d+") {
            $findings.Info += @{
                File = $file
                Issue = "No USER directive - container runs as root"
                Suggestion = "Consider adding non-root user for security"
            }
        }
        
        # Check for HEALTHCHECK
        if ($content -notmatch "HEALTHCHECK") {
            $findings.Info += @{
                File = $file
                Issue = "No HEALTHCHECK defined"
                Suggestion = "Add HEALTHCHECK for container orchestration"
            }
        }
    }
    
    # -----------------------------------------
    # Kubernetes Manifest Checks
    # -----------------------------------------
    
    if ($file -match "\.yaml$" -and $file -match "kubernetes/") {
        # Check for resource limits
        if ($content -match "kind:\s*Deployment" -and $content -notmatch "resources:") {
            $findings.Warning += @{
                File = $file
                Issue = "No resource limits defined"
                Suggestion = "Add resources.requests and resources.limits"
            }
        }
        
        # Check for labels
        if ($content -match "kind:\s*(Deployment|Service)" -and $content -notmatch "app\.kubernetes\.io/") {
            $findings.Info += @{
                File = $file
                Issue = "Missing recommended Kubernetes labels"
                Suggestion = "Add app.kubernetes.io/name, version, component labels"
            }
        }
        
        # Check for image pull policy
        if ($content -match "image:" -and $content -notmatch "imagePullPolicy:") {
            $findings.Info += @{
                File = $file
                Issue = "No imagePullPolicy specified"
                Suggestion = "Explicitly set imagePullPolicy (IfNotPresent recommended)"
            }
        }
    }
    
    # -----------------------------------------
    # PowerShell Checks
    # -----------------------------------------
    
    if ($file -match "\.ps1$") {
        # Check for error handling
        if ($content -notmatch "try\s*{" -and $content -notmatch "-ErrorAction") {
            $findings.Info += @{
                File = $file
                Issue = "Limited error handling detected"
                Suggestion = "Add try/catch blocks or -ErrorAction parameters"
            }
        }
        
        # Check for Write-Host vs Write-Output
        if ($content -match "Write-Host" -and $content -notmatch "Write-Output") {
            $findings.Info += @{
                File = $file
                Issue = "Using Write-Host (not pipeline-friendly)"
                Suggestion = "Consider Write-Output for pipeline compatibility"
            }
        }
    }
    
    # -----------------------------------------
    # Python Checks
    # -----------------------------------------
    
    if ($file -match "\.py$") {
        # Check for exception handling
        if ($content -match "except:" -and $content -notmatch "except\s+\w+") {
            $findings.Warning += @{
                File = $file
                Issue = "Bare 'except:' clause (catches all exceptions)"
                Suggestion = "Catch specific exceptions"
            }
        }
        
        # Check for print statements (should use logging)
        if ($content -match "^\s*print\(" -and $content -notmatch "import logging") {
            $findings.Info += @{
                File = $file
                Issue = "Using print() instead of logging"
                Suggestion = "Use logging module for production code"
            }
        }
    }
}

# ===========================================
# Report Results
# ===========================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "REVIEW FINDINGS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Blocking issues
if ($findings.Blocking.Count -gt 0) {
    Write-Host "`nBLOCKING ISSUES ($($findings.Blocking.Count)):" -ForegroundColor Red
    foreach ($finding in $findings.Blocking) {
        Write-Host "`n  ✗ $($finding.File)" -ForegroundColor Red
        Write-Host "    Issue: $($finding.Issue)"
        Write-Host "    Fix: $($finding.Suggestion)" -ForegroundColor Yellow
    }
}

# Warnings
if ($findings.Warning.Count -gt 0) {
    Write-Host "`nWARNINGS ($($findings.Warning.Count)):" -ForegroundColor Yellow
    foreach ($finding in $findings.Warning) {
        Write-Host "`n  ! $($finding.File)" -ForegroundColor Yellow
        Write-Host "    Issue: $($finding.Issue)"
        Write-Host "    Suggestion: $($finding.Suggestion)" -ForegroundColor Gray
    }
}

# Info/Suggestions
if ($findings.Info.Count -gt 0) {
    Write-Host "`nSUGGESTIONS ($($findings.Info.Count)):" -ForegroundColor Cyan
    foreach ($finding in $findings.Info) {
        Write-Host "`n  → $($finding.File)" -ForegroundColor Cyan
        Write-Host "    Note: $($finding.Issue)"
        Write-Host "    Consider: $($finding.Suggestion)" -ForegroundColor Gray
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "REVIEW SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Files Reviewed: $($ChangedFiles.Count)"
Write-Host "Blocking Issues: $($findings.Blocking.Count)"
Write-Host "Warnings: $($findings.Warning.Count)"
Write-Host "Suggestions: $($findings.Info.Count)"

if ($findings.Blocking.Count -gt 0) {
    Write-Host "`nRECOMMENDATION: REQUEST CHANGES" -ForegroundColor Red
    Write-Host "Blocking issues must be resolved before merge."
    return $false
}
elseif ($findings.Warning.Count -gt 0) {
    Write-Host "`nRECOMMENDATION: APPROVE WITH COMMENTS" -ForegroundColor Yellow
    Write-Host "Warnings should be addressed but are not blocking."
    return $true
}
else {
    Write-Host "`nRECOMMENDATION: APPROVE" -ForegroundColor Green
    Write-Host "No significant issues found."
    return $true
}
