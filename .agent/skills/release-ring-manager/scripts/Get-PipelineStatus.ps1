<#
.SYNOPSIS
    Retrieves status of Azure DevOps pipelines and recent runs.

.DESCRIPTION
    Queries Azure DevOps for pipeline definitions and recent run status.
    Helps identify failing pipelines and deployment issues.

.PARAMETER Organization
    Azure DevOps organization name.

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER PipelineName
    Optional specific pipeline to check.

.PARAMETER IncludeRuns
    Number of recent runs to include (default: 3).

.EXAMPLE
    .\Get-PipelineStatus.ps1 -Organization "<your-org>" -Project "IPC-Platform-Engineering"

.EXAMPLE
    .\Get-PipelineStatus.ps1 -Organization "<your-org>" -Project "IPC-Platform-Engineering" -PipelineName "build-containers"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    
    [Parameter(Mandatory = $true)]
    [string]$Project,
    
    [string]$PipelineName,
    
    [int]$IncludeRuns = 3
)

$OrgUrl = "https://dev.azure.com/$Organization"

Write-Host "`nPIPELINE STATUS REPORT" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host "Organization: $Organization"
Write-Host "Project: $Project`n"

# Check if Azure CLI is available and logged in
try {
    $azAccount = az account show 2>$null | ConvertFrom-Json
    if (-not $azAccount) {
        Write-Host "ERROR: Not logged in to Azure CLI. Run 'az login' first." -ForegroundColor Red
        return
    }
}
catch {
    Write-Host "ERROR: Azure CLI not available." -ForegroundColor Red
    return
}

# Check if Azure DevOps extension is installed
$devopsExtension = az extension list --query "[?name=='azure-devops']" 2>$null | ConvertFrom-Json
if (-not $devopsExtension) {
    Write-Host "Installing Azure DevOps CLI extension..." -ForegroundColor Yellow
    az extension add --name azure-devops
}

# Set default organization
az devops configure --defaults organization=$OrgUrl project=$Project 2>$null

# Get pipelines
Write-Host "Fetching pipelines..." -ForegroundColor Yellow

try {
    if ($PipelineName) {
        $pipelines = az pipelines list --query "[?name=='$PipelineName']" 2>$null | ConvertFrom-Json
    }
    else {
        $pipelines = az pipelines list 2>$null | ConvertFrom-Json
    }
}
catch {
    Write-Host "ERROR: Failed to fetch pipelines. Check your permissions." -ForegroundColor Red
    return
}

if (-not $pipelines -or $pipelines.Count -eq 0) {
    Write-Host "No pipelines found." -ForegroundColor Yellow
    return
}

Write-Host "Found $($pipelines.Count) pipeline(s)`n" -ForegroundColor Green

# Process each pipeline
foreach ($pipeline in $pipelines) {
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Write-Host "Pipeline: $($pipeline.name)" -ForegroundColor White
    Write-Host "ID: $($pipeline.id)"
    Write-Host "Path: $($pipeline.path)"
    
    # Get recent runs
    try {
        $runs = az pipelines runs list --pipeline-ids $pipeline.id --top $IncludeRuns 2>$null | ConvertFrom-Json
    }
    catch {
        Write-Host "  Could not fetch runs." -ForegroundColor Yellow
        continue
    }
    
    if ($runs -and $runs.Count -gt 0) {
        Write-Host "`nRecent Runs:" -ForegroundColor Yellow
        
        foreach ($run in $runs) {
            $statusColor = switch ($run.result) {
                "succeeded" { "Green" }
                "failed" { "Red" }
                "canceled" { "Yellow" }
                default { "White" }
            }
            
            $status = if ($run.result) { $run.result } else { $run.status }
            $finishTime = if ($run.finishTime) { 
                [datetime]::Parse($run.finishTime).ToString("yyyy-MM-dd HH:mm") 
            } else { 
                "In Progress" 
            }
            
            Write-Host "  [$status] " -ForegroundColor $statusColor -NoNewline
            Write-Host "Run #$($run.id) - $finishTime"
            Write-Host "    Branch: $($run.sourceBranch)"
            Write-Host "    Triggered: $($run.reason)"
        }
        
        # Summary
        $lastRun = $runs[0]
        $healthStatus = switch ($lastRun.result) {
            "succeeded" { "HEALTHY" }
            "failed" { "FAILING" }
            default { "UNKNOWN" }
        }
        $healthColor = switch ($healthStatus) {
            "HEALTHY" { "Green" }
            "FAILING" { "Red" }
            default { "Yellow" }
        }
        
        Write-Host "`nHealth Status: " -NoNewline
        Write-Host $healthStatus -ForegroundColor $healthColor
    }
    else {
        Write-Host "`nNo recent runs found." -ForegroundColor Yellow
        Write-Host "Health Status: NOT RUN" -ForegroundColor Yellow
    }
}

# GitOps Status Check
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "GITOPS DEPLOYMENT STATUS" -ForegroundColor Cyan

# Check if kubectl is available
$kubectlAvailable = Get-Command kubectl -ErrorAction SilentlyContinue
if ($kubectlAvailable) {
    Write-Host "`nChecking Flux sync status..." -ForegroundColor Yellow
    
    try {
        $gitRepos = kubectl get gitrepositories -n flux-system -o json 2>$null | ConvertFrom-Json
        if ($gitRepos.items) {
            foreach ($repo in $gitRepos.items) {
                $ready = ($repo.status.conditions | Where-Object { $_.type -eq "Ready" }).status
                $statusColor = if ($ready -eq "True") { "Green" } else { "Red" }
                Write-Host "  GitRepository: $($repo.metadata.name) - Ready: " -NoNewline
                Write-Host $ready -ForegroundColor $statusColor
            }
        }
        
        $kustomizations = kubectl get kustomizations -n flux-system -o json 2>$null | ConvertFrom-Json
        if ($kustomizations.items) {
            foreach ($ks in $kustomizations.items) {
                $ready = ($ks.status.conditions | Where-Object { $_.type -eq "Ready" }).status
                $statusColor = if ($ready -eq "True") { "Green" } else { "Red" }
                Write-Host "  Kustomization: $($ks.metadata.name) - Ready: " -NoNewline
                Write-Host $ready -ForegroundColor $statusColor
            }
        }
    }
    catch {
        Write-Host "  Could not connect to Kubernetes cluster." -ForegroundColor Yellow
    }
}
else {
    Write-Host "  kubectl not available - skipping GitOps check" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Report complete." -ForegroundColor Green
