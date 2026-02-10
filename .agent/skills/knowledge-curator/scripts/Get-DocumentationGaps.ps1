<#
.SYNOPSIS
    Analyzes recent code changes and identifies documentation gaps.

.DESCRIPTION
    Compares Git commit history against documentation files to find
    areas where documentation may need updating.

.PARAMETER SinceCommit
    Git commit hash or reference to compare from (default: HEAD~5).

.PARAMETER DocsPath
    Path to documentation directory (default: .\docs).

.EXAMPLE
    .\Get-DocumentationGaps.ps1 -SinceCommit "HEAD~10"

.EXAMPLE
    .\Get-DocumentationGaps.ps1 -SinceCommit "abc1234"
#>

param(
    [string]$SinceCommit = "HEAD~5",
    [string]$DocsPath = ".\docs"
)

# Mapping of code paths to documentation files
$PathToDocMapping = @{
    "docker/opcua-simulator"     = "05-Workloads-OPC-UA.md"
    "docker/opcua-gateway"       = "05-Workloads-OPC-UA.md"
    "docker/health-monitor"      = "06-Workloads-Monitoring.md"
    "docker/log-forwarder"       = "06-Workloads-Monitoring.md"
    "docker/anomaly-detection"   = "07-Workloads-Analytics.md"
    "docker/test-data-collector" = "07-Workloads-Analytics.md"
    "kubernetes/"                = "03-Edge-Deployment.md", "04-GitOps-Configuration.md"
    "packer/"                    = "02-Golden-Image-Pipeline.md"
    "pipelines/"                 = "08-CI-CD-Pipelines.md"
    "compliance/"                = "09-Compliance-as-a-Service.md"
}

Write-Host "`nDOCUMENTATION GAP ANALYSIS" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host "Analyzing changes since: $SinceCommit`n"

# Get changed files
try {
    $changedFiles = git diff --name-only $SinceCommit HEAD 2>$null
    if (-not $changedFiles) {
        Write-Host "No changes found since $SinceCommit" -ForegroundColor Yellow
        return
    }
}
catch {
    Write-Host "ERROR: Unable to get Git diff. Are you in a Git repository?" -ForegroundColor Red
    return
}

Write-Host "Changed Files:" -ForegroundColor Yellow
$changedFiles | ForEach-Object { Write-Host "  $_" }

# Identify affected documentation
$affectedDocs = @{}
$codeChanges = @()
$docChanges = @()

foreach ($file in $changedFiles) {
    # Separate code changes from doc changes
    if ($file -match "\.md$") {
        $docChanges += $file
    }
    else {
        $codeChanges += $file
        
        # Find matching documentation
        foreach ($pattern in $PathToDocMapping.Keys) {
            if ($file -like "$pattern*") {
                $docs = $PathToDocMapping[$pattern]
                if ($docs -is [array]) {
                    foreach ($doc in $docs) {
                        $affectedDocs[$doc] = $true
                    }
                }
                else {
                    $affectedDocs[$docs] = $true
                }
            }
        }
    }
}

# Report findings
Write-Host "`n----------------------------------------" -ForegroundColor Cyan

Write-Host "`nCode Changes: $($codeChanges.Count) files" -ForegroundColor Yellow
Write-Host "Documentation Changes: $($docChanges.Count) files" -ForegroundColor Yellow

if ($affectedDocs.Count -gt 0) {
    Write-Host "`nDocumentation Potentially Needing Updates:" -ForegroundColor Yellow
    foreach ($doc in $affectedDocs.Keys | Sort-Object) {
        $docPath = Join-Path $DocsPath $doc
        if (Test-Path $docPath) {
            $lastModified = (Get-Item $docPath).LastWriteTime
            Write-Host "  - $doc (last modified: $lastModified)" -ForegroundColor White
        }
        else {
            Write-Host "  - $doc (file not found in $DocsPath)" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "`nNo documentation mapping found for changed files." -ForegroundColor Yellow
    Write-Host "Manual review may be needed."
}

# Check for new files that might need documentation
$newFiles = git diff --name-only --diff-filter=A $SinceCommit HEAD 2>$null
if ($newFiles) {
    Write-Host "`nNew Files Added (may need documentation):" -ForegroundColor Yellow
    $newFiles | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
}

# Summary
Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "RECOMMENDED ACTIONS:" -ForegroundColor Cyan

if ($affectedDocs.Count -gt 0) {
    Write-Host "1. Review and update the following documentation:" -ForegroundColor White
    foreach ($doc in $affectedDocs.Keys | Sort-Object) {
        Write-Host "   - $doc"
    }
}

if ($codeChanges.Count -gt 0 -and $docChanges.Count -eq 0) {
    Write-Host "2. WARNING: Code changed but no documentation updated!" -ForegroundColor Yellow
}

if ($newFiles) {
    Write-Host "3. Document new files/features added to the project." -ForegroundColor White
}

# Return affected docs for programmatic use
return $affectedDocs.Keys
