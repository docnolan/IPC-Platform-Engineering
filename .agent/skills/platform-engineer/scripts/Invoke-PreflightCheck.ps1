<#
.SYNOPSIS
    Comprehensive preflight check for platform engineering tasks.

.DESCRIPTION
    Validates environment readiness for edge platform engineering work including
    Git status, cloud CLIs, container tools, orchestration tools, and IaC tools.

.PARAMETER Scope
    Check scope: Minimal, Standard, or Full (default: Standard).

.PARAMETER TargetCloud
    Target cloud platform: Azure, AWS, GCP, or All (default: Azure).

.EXAMPLE
    .\Invoke-PreflightCheck.ps1

.EXAMPLE
    .\Invoke-PreflightCheck.ps1 -Scope Full -TargetCloud All
#>

param(
    [ValidateSet("Minimal", "Standard", "Full")]
    [string]$Scope = "Standard",
    
    [ValidateSet("Azure", "AWS", "GCP", "All")]
    [string]$TargetCloud = "Azure"
)

Write-Host "`nPLATFORM ENGINEERING PREFLIGHT CHECK" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Scope: $Scope"
Write-Host "Target Cloud: $TargetCloud"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

$results = @{
    Passed = @()
    Warning = @()
    Failed = @()
}

function Test-Command {
    param([string]$Command, [string]$Name, [string]$VersionArg = "--version")
    
    $exists = Get-Command $Command -ErrorAction SilentlyContinue
    if ($exists) {
        try {
            $version = & $Command $VersionArg 2>&1 | Select-Object -First 1
            return @{ Status = "Pass"; Version = $version }
        }
        catch {
            return @{ Status = "Pass"; Version = "unknown" }
        }
    }
    return @{ Status = "Fail"; Version = $null }
}

# ===========================================
# Git Status (Always checked)
# ===========================================
Write-Host "--- Git Repository ---" -ForegroundColor Yellow

$gitCheck = Test-Command "git" "Git"
if ($gitCheck.Status -eq "Pass") {
    Write-Host "  ✓ Git: $($gitCheck.Version)" -ForegroundColor Green
    $results.Passed += "Git"
    
    # Check if in a git repo
    $inRepo = git rev-parse --is-inside-work-tree 2>$null
    if ($inRepo -eq "true") {
        Write-Host "  ✓ Inside Git repository" -ForegroundColor Green
        
        # Check for uncommitted changes
        $status = git status --porcelain
        if ($status) {
            Write-Host "  ! Uncommitted changes detected ($($status.Count) files)" -ForegroundColor Yellow
            $results.Warning += "Uncommitted Git changes"
        }
        else {
            Write-Host "  ✓ Working directory clean" -ForegroundColor Green
        }
        
        # Check current branch
        $branch = git branch --show-current
        Write-Host "  ℹ Current branch: $branch" -ForegroundColor Cyan
    }
    else {
        Write-Host "  ! Not inside a Git repository" -ForegroundColor Yellow
        $results.Warning += "Not in Git repository"
    }
}
else {
    Write-Host "  ✗ Git not found" -ForegroundColor Red
    $results.Failed += "Git"
}

# ===========================================
# Container Tools
# ===========================================
Write-Host "`n--- Container Tools ---" -ForegroundColor Yellow

$dockerCheck = Test-Command "docker" "Docker"
if ($dockerCheck.Status -eq "Pass") {
    Write-Host "  ✓ Docker: Available" -ForegroundColor Green
    $results.Passed += "Docker"
    
    # Check Docker daemon
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Docker daemon running" -ForegroundColor Green
    }
    else {
        Write-Host "  ! Docker daemon not running" -ForegroundColor Yellow
        $results.Warning += "Docker daemon not running"
    }
}
else {
    Write-Host "  ✗ Docker not found" -ForegroundColor Red
    $results.Failed += "Docker"
}

# Podman (alternative)
$podmanCheck = Test-Command "podman" "Podman"
if ($podmanCheck.Status -eq "Pass") {
    Write-Host "  ✓ Podman: Available (alternative)" -ForegroundColor Green
    $results.Passed += "Podman"
}

# ===========================================
# Kubernetes Tools
# ===========================================
Write-Host "`n--- Kubernetes Tools ---" -ForegroundColor Yellow

$kubectlCheck = Test-Command "kubectl" "kubectl"
if ($kubectlCheck.Status -eq "Pass") {
    Write-Host "  ✓ kubectl: $($kubectlCheck.Version)" -ForegroundColor Green
    $results.Passed += "kubectl"
    
    # Check cluster connectivity
    $clusterInfo = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Kubernetes cluster connected" -ForegroundColor Green
    }
    else {
        Write-Host "  ! No Kubernetes cluster connection" -ForegroundColor Yellow
        $results.Warning += "No K8s cluster connection"
    }
}
else {
    Write-Host "  ✗ kubectl not found" -ForegroundColor Red
    $results.Failed += "kubectl"
}

$helmCheck = Test-Command "helm" "Helm"
if ($helmCheck.Status -eq "Pass") {
    Write-Host "  ✓ Helm: $($helmCheck.Version)" -ForegroundColor Green
    $results.Passed += "Helm"
}
else {
    Write-Host "  - Helm not found (optional)" -ForegroundColor Gray
}

if ($Scope -eq "Full") {
    $fluxCheck = Test-Command "flux" "Flux"
    if ($fluxCheck.Status -eq "Pass") {
        Write-Host "  ✓ Flux CLI: Available" -ForegroundColor Green
        $results.Passed += "Flux"
    }
    else {
        Write-Host "  - Flux CLI not found (optional)" -ForegroundColor Gray
    }
    
    $kustomizeCheck = Test-Command "kustomize" "Kustomize"
    if ($kustomizeCheck.Status -eq "Pass") {
        Write-Host "  ✓ Kustomize: Available" -ForegroundColor Green
        $results.Passed += "Kustomize"
    }
}

# ===========================================
# Infrastructure-as-Code Tools
# ===========================================
Write-Host "`n--- Infrastructure-as-Code ---" -ForegroundColor Yellow

$terraformCheck = Test-Command "terraform" "Terraform"
if ($terraformCheck.Status -eq "Pass") {
    Write-Host "  ✓ Terraform: $($terraformCheck.Version)" -ForegroundColor Green
    $results.Passed += "Terraform"
}
else {
    Write-Host "  - Terraform not found" -ForegroundColor Gray
}

$packerCheck = Test-Command "packer" "Packer"
if ($packerCheck.Status -eq "Pass") {
    Write-Host "  ✓ Packer: $($packerCheck.Version)" -ForegroundColor Green
    $results.Passed += "Packer"
}
else {
    Write-Host "  - Packer not found" -ForegroundColor Gray
}

if ($Scope -eq "Full") {
    $pulumiCheck = Test-Command "pulumi" "Pulumi"
    if ($pulumiCheck.Status -eq "Pass") {
        Write-Host "  ✓ Pulumi: Available" -ForegroundColor Green
        $results.Passed += "Pulumi"
    }
    
    $ansibleCheck = Test-Command "ansible" "Ansible"
    if ($ansibleCheck.Status -eq "Pass") {
        Write-Host "  ✓ Ansible: Available" -ForegroundColor Green
        $results.Passed += "Ansible"
    }
}

# ===========================================
# Cloud CLIs
# ===========================================
Write-Host "`n--- Cloud CLIs ---" -ForegroundColor Yellow

if ($TargetCloud -eq "Azure" -or $TargetCloud -eq "All") {
    $azCheck = Test-Command "az" "Azure CLI"
    if ($azCheck.Status -eq "Pass") {
        Write-Host "  ✓ Azure CLI: Available" -ForegroundColor Green
        $results.Passed += "Azure CLI"
        
        # Check login status
        $azAccount = az account show 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($azAccount) {
            Write-Host "  ✓ Azure: Logged in as $($azAccount.user.name)" -ForegroundColor Green
            Write-Host "    Subscription: $($azAccount.name)" -ForegroundColor Gray
        }
        else {
            Write-Host "  ! Azure: Not logged in" -ForegroundColor Yellow
            $results.Warning += "Azure not logged in"
        }
    }
    else {
        Write-Host "  ✗ Azure CLI not found" -ForegroundColor Red
        $results.Failed += "Azure CLI"
    }
}

if ($TargetCloud -eq "AWS" -or $TargetCloud -eq "All") {
    $awsCheck = Test-Command "aws" "AWS CLI"
    if ($awsCheck.Status -eq "Pass") {
        Write-Host "  ✓ AWS CLI: Available" -ForegroundColor Green
        $results.Passed += "AWS CLI"
        
        $awsIdentity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($awsIdentity) {
            Write-Host "  ✓ AWS: Authenticated" -ForegroundColor Green
        }
        else {
            Write-Host "  ! AWS: Not authenticated" -ForegroundColor Yellow
            $results.Warning += "AWS not authenticated"
        }
    }
    else {
        Write-Host "  - AWS CLI not found" -ForegroundColor Gray
    }
}

if ($TargetCloud -eq "GCP" -or $TargetCloud -eq "All") {
    $gcloudCheck = Test-Command "gcloud" "Google Cloud CLI"
    if ($gcloudCheck.Status -eq "Pass") {
        Write-Host "  ✓ Google Cloud CLI: Available" -ForegroundColor Green
        $results.Passed += "GCloud CLI"
    }
    else {
        Write-Host "  - Google Cloud CLI not found" -ForegroundColor Gray
    }
}

# ===========================================
# Programming Languages
# ===========================================
if ($Scope -ne "Minimal") {
    Write-Host "`n--- Programming Languages ---" -ForegroundColor Yellow
    
    $pythonCheck = Test-Command "python" "Python"
    if ($pythonCheck.Status -eq "Pass") {
        Write-Host "  ✓ Python: $($pythonCheck.Version)" -ForegroundColor Green
        $results.Passed += "Python"
    }
    else {
        Write-Host "  - Python not found" -ForegroundColor Gray
    }
    
    $goCheck = Test-Command "go" "Go" "version"
    if ($goCheck.Status -eq "Pass") {
        Write-Host "  ✓ Go: $($goCheck.Version)" -ForegroundColor Green
        $results.Passed += "Go"
    }
    else {
        Write-Host "  - Go not found" -ForegroundColor Gray
    }
    
    if ($Scope -eq "Full") {
        $rustCheck = Test-Command "rustc" "Rust"
        if ($rustCheck.Status -eq "Pass") {
            Write-Host "  ✓ Rust: $($rustCheck.Version)" -ForegroundColor Green
            $results.Passed += "Rust"
        }
        else {
            Write-Host "  - Rust not found" -ForegroundColor Gray
        }
    }
}

# ===========================================
# Observability Tools
# ===========================================
if ($Scope -eq "Full") {
    Write-Host "`n--- Observability Tools ---" -ForegroundColor Yellow
    
    # Check for common observability CLIs
    $promtoolCheck = Test-Command "promtool" "Prometheus"
    if ($promtoolCheck.Status -eq "Pass") {
        Write-Host "  ✓ Promtool: Available" -ForegroundColor Green
    }
    
    # Datadog
    $datadogCheck = Test-Command "datadog-ci" "Datadog CI"
    if ($datadogCheck.Status -eq "Pass") {
        Write-Host "  ✓ Datadog CI: Available" -ForegroundColor Green
    }
}

# ===========================================
# Summary
# ===========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PREFLIGHT CHECK SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nPassed: $($results.Passed.Count)" -ForegroundColor Green
Write-Host "Warnings: $($results.Warning.Count)" -ForegroundColor Yellow
Write-Host "Failed: $($results.Failed.Count)" -ForegroundColor Red

if ($results.Failed.Count -gt 0) {
    Write-Host "`nFailed Checks:" -ForegroundColor Red
    $results.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($results.Warning.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $results.Warning | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

# Overall readiness
$criticalTools = @("Git", "Docker", "kubectl")
$missingCritical = $criticalTools | Where-Object { $_ -in $results.Failed }

if ($missingCritical.Count -gt 0) {
    Write-Host "`nSTATUS: NOT READY" -ForegroundColor Red
    Write-Host "Missing critical tools: $($missingCritical -join ', ')"
    return $false
}
elseif ($results.Warning.Count -gt 0) {
    Write-Host "`nSTATUS: READY WITH WARNINGS" -ForegroundColor Yellow
    return $true
}
else {
    Write-Host "`nSTATUS: READY" -ForegroundColor Green
    return $true
}
