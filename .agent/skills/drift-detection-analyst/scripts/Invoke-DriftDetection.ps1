<#
.SYNOPSIS
    Detects configuration drift between Git manifests and cluster state.

.DESCRIPTION
    Compares Kubernetes resources defined in Git with actual cluster state.
    Identifies resources that have drifted, unexpected resources, and missing resources.

.PARAMETER ManifestPath
    Path to kubernetes manifests directory (default: .\kubernetes\workloads).

.PARAMETER Namespace
    Kubernetes namespace to check (default: dmc-workloads).

.PARAMETER IncludeFluxStatus
    Also check Flux GitRepository and Kustomization status.

.EXAMPLE
    .\Invoke-DriftDetection.ps1

.EXAMPLE
    .\Invoke-DriftDetection.ps1 -Namespace "dmc-workloads" -IncludeFluxStatus
#>

param(
    [string]$ManifestPath = ".\kubernetes\workloads",
    [string]$Namespace = "dmc-workloads",
    [switch]$IncludeFluxStatus
)

Write-Host "`nDRIFT DETECTION ANALYSIS" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Manifest Path: $ManifestPath"
Write-Host "Namespace: $Namespace"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# Check kubectl availability
$kubectlAvailable = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectlAvailable) {
    Write-Host "ERROR: kubectl not found. Cannot perform drift detection." -ForegroundColor Red
    return
}

# Check cluster connectivity
try {
    $nodes = kubectl get nodes --no-headers 2>$null
    if (-not $nodes) {
        Write-Host "ERROR: Cannot connect to Kubernetes cluster." -ForegroundColor Red
        return
    }
    Write-Host "Cluster connected: Yes" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Cluster connection failed." -ForegroundColor Red
    return
}

# Flux Status Check
if ($IncludeFluxStatus) {
    Write-Host "`n--- FLUX STATUS ---" -ForegroundColor Yellow
    
    # GitRepository status
    $gitRepos = kubectl get gitrepositories -n flux-system -o json 2>$null | ConvertFrom-Json
    if ($gitRepos.items) {
        foreach ($repo in $gitRepos.items) {
            $readyCondition = $repo.status.conditions | Where-Object { $_.type -eq "Ready" }
            $ready = $readyCondition.status
            $message = $readyCondition.message
            $revision = $repo.status.artifact.revision
            
            $statusColor = if ($ready -eq "True") { "Green" } else { "Red" }
            Write-Host "GitRepository: $($repo.metadata.name)" -ForegroundColor White
            Write-Host "  Ready: " -NoNewline
            Write-Host $ready -ForegroundColor $statusColor
            Write-Host "  Revision: $revision"
            if ($ready -ne "True") {
                Write-Host "  Message: $message" -ForegroundColor Yellow
            }
        }
    }
    
    # Kustomization status
    $kustomizations = kubectl get kustomizations -n flux-system -o json 2>$null | ConvertFrom-Json
    if ($kustomizations.items) {
        foreach ($ks in $kustomizations.items) {
            $readyCondition = $ks.status.conditions | Where-Object { $_.type -eq "Ready" }
            $ready = $readyCondition.status
            $message = $readyCondition.message
            
            $statusColor = if ($ready -eq "True") { "Green" } else { "Red" }
            Write-Host "Kustomization: $($ks.metadata.name)" -ForegroundColor White
            Write-Host "  Ready: " -NoNewline
            Write-Host $ready -ForegroundColor $statusColor
            if ($ready -ne "True") {
                Write-Host "  Message: $message" -ForegroundColor Yellow
            }
        }
    }
}

# Get expected deployments from manifests
Write-Host "`n--- MANIFEST ANALYSIS ---" -ForegroundColor Yellow

$expectedDeployments = @{}
if (Test-Path $ManifestPath) {
    $deploymentFiles = Get-ChildItem -Path $ManifestPath -Recurse -Filter "deployment.yaml"
    foreach ($file in $deploymentFiles) {
        # Simple YAML parsing - extract deployment name
        $content = Get-Content $file.FullName -Raw
        if ($content -match "kind:\s*Deployment" -and $content -match "name:\s*(\S+)") {
            $deploymentName = $Matches[1]
            
            # Extract image
            $image = "unknown"
            if ($content -match "image:\s*(\S+)") {
                $image = $Matches[1]
            }
            
            $expectedDeployments[$deploymentName] = @{
                File = $file.FullName
                Image = $image
            }
            Write-Host "  Expected: $deploymentName"
        }
    }
}
else {
    Write-Host "  WARNING: Manifest path not found: $ManifestPath" -ForegroundColor Yellow
}

# Get actual deployments from cluster
Write-Host "`n--- CLUSTER STATE ---" -ForegroundColor Yellow

$actualDeployments = @{}
$clusterDeploys = kubectl get deployments -n $Namespace -o json 2>$null | ConvertFrom-Json

if ($clusterDeploys.items) {
    foreach ($deploy in $clusterDeploys.items) {
        $name = $deploy.metadata.name
        $image = $deploy.spec.template.spec.containers[0].image
        $replicas = $deploy.spec.replicas
        $ready = $deploy.status.readyReplicas
        
        $actualDeployments[$name] = @{
            Image = $image
            Replicas = $replicas
            Ready = $ready
        }
        Write-Host "  Found: $name (image: $($image.Split(':')[-1]))"
    }
}
else {
    Write-Host "  No deployments found in namespace $Namespace" -ForegroundColor Yellow
}

# Compare and detect drift
Write-Host "`n--- DRIFT ANALYSIS ---" -ForegroundColor Yellow

$inSync = @()
$drifted = @()
$unexpected = @()
$missing = @()

# Check expected vs actual
foreach ($expected in $expectedDeployments.Keys) {
    if ($actualDeployments.ContainsKey($expected)) {
        $expectedImage = $expectedDeployments[$expected].Image
        $actualImage = $actualDeployments[$expected].Image
        
        if ($expectedImage -eq $actualImage -or $expectedImage -eq "unknown") {
            $inSync += $expected
        }
        else {
            $drifted += @{
                Name = $expected
                Expected = $expectedImage
                Actual = $actualImage
            }
        }
    }
    else {
        $missing += $expected
    }
}

# Check for unexpected resources
foreach ($actual in $actualDeployments.Keys) {
    if (-not $expectedDeployments.ContainsKey($actual)) {
        $unexpected += $actual
    }
}

# Report Results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DRIFT DETECTION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($inSync.Count -gt 0) {
    Write-Host "`nIN SYNC ($($inSync.Count)):" -ForegroundColor Green
    foreach ($resource in $inSync) {
        Write-Host "  ✓ deployment/$resource" -ForegroundColor Green
    }
}

if ($drifted.Count -gt 0) {
    Write-Host "`nDRIFTED ($($drifted.Count)):" -ForegroundColor Red
    foreach ($resource in $drifted) {
        Write-Host "  ✗ deployment/$($resource.Name)" -ForegroundColor Red
        Write-Host "    Expected: $($resource.Expected)" -ForegroundColor Yellow
        Write-Host "    Actual:   $($resource.Actual)" -ForegroundColor Yellow
    }
}

if ($unexpected.Count -gt 0) {
    Write-Host "`nUNEXPECTED (not in Git) ($($unexpected.Count)):" -ForegroundColor Yellow
    foreach ($resource in $unexpected) {
        Write-Host "  ? deployment/$resource" -ForegroundColor Yellow
    }
}

if ($missing.Count -gt 0) {
    Write-Host "`nMISSING (in Git, not in cluster) ($($missing.Count)):" -ForegroundColor Red
    foreach ($resource in $missing) {
        Write-Host "  ! deployment/$resource" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
$totalIssues = $drifted.Count + $unexpected.Count + $missing.Count

if ($totalIssues -eq 0) {
    Write-Host "STATUS: ALL RESOURCES IN SYNC" -ForegroundColor Green
    return $true
}
else {
    Write-Host "STATUS: DRIFT DETECTED ($totalIssues issues)" -ForegroundColor Red
    Write-Host "`nRecommended Actions:" -ForegroundColor Yellow
    
    if ($drifted.Count -gt 0) {
        Write-Host "  1. Force Flux reconciliation to restore drifted resources"
    }
    if ($unexpected.Count -gt 0) {
        Write-Host "  2. Investigate unexpected resources - may need deletion or Git commit"
    }
    if ($missing.Count -gt 0) {
        Write-Host "  3. Check Flux logs for apply failures on missing resources"
    }
    
    return $false
}
