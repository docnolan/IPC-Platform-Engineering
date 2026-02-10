<#
.SYNOPSIS
    Retrieves health status of all IPC Platform workloads.

.DESCRIPTION
    Queries Kubernetes cluster for pod status, restart counts, resource usage,
    and recent events. Produces a health report identifying issues.

.PARAMETER Namespace
    Kubernetes namespace to check (default: dmc-workloads).

.PARAMETER IncludeEvents
    Include recent Kubernetes events in the report.

.PARAMETER IncludeLogs
    Include recent log snippets from unhealthy pods.

.EXAMPLE
    .\Get-WorkloadHealth.ps1

.EXAMPLE
    .\Get-WorkloadHealth.ps1 -Namespace "dmc-workloads" -IncludeEvents -IncludeLogs
#>

param(
    [string]$Namespace = "dmc-workloads",
    [switch]$IncludeEvents,
    [switch]$IncludeLogs
)

Write-Host "`nWORKLOAD HEALTH REPORT" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host "Namespace: $Namespace"
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# Check kubectl availability
$kubectlAvailable = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectlAvailable) {
    Write-Host "ERROR: kubectl not found." -ForegroundColor Red
    return
}

# Check cluster connectivity
try {
    $nodes = kubectl get nodes -o json 2>$null | ConvertFrom-Json
    if (-not $nodes.items) {
        Write-Host "ERROR: Cannot connect to Kubernetes cluster." -ForegroundColor Red
        return
    }
}
catch {
    Write-Host "ERROR: Cluster connection failed." -ForegroundColor Red
    return
}

# Node Health
Write-Host "--- NODE HEALTH ---" -ForegroundColor Yellow
foreach ($node in $nodes.items) {
    $name = $node.metadata.name
    $readyCondition = $node.status.conditions | Where-Object { $_.type -eq "Ready" }
    $ready = $readyCondition.status
    
    $statusColor = if ($ready -eq "True") { "Green" } else { "Red" }
    Write-Host "  $name : " -NoNewline
    Write-Host $(if ($ready -eq "True") { "Ready" } else { "NotReady" }) -ForegroundColor $statusColor
}

# Get pods
Write-Host "`n--- POD STATUS ---" -ForegroundColor Yellow
$pods = kubectl get pods -n $Namespace -o json 2>$null | ConvertFrom-Json

if (-not $pods.items -or $pods.items.Count -eq 0) {
    Write-Host "  No pods found in namespace $Namespace" -ForegroundColor Yellow
    return
}

$healthyPods = @()
$unhealthyPods = @()

foreach ($pod in $pods.items) {
    $name = $pod.metadata.name
    $phase = $pod.status.phase
    $restarts = 0
    $containerStatus = "Unknown"
    
    if ($pod.status.containerStatuses) {
        $restarts = ($pod.status.containerStatuses | Measure-Object -Property restartCount -Sum).Sum
        $waiting = $pod.status.containerStatuses | Where-Object { $_.state.waiting }
        if ($waiting) {
            $containerStatus = $waiting.state.waiting.reason
        }
        else {
            $containerStatus = "Running"
        }
    }
    
    $isHealthy = ($phase -eq "Running") -and ($containerStatus -eq "Running") -and ($restarts -lt 5)
    
    $podInfo = @{
        Name = $name
        Phase = $phase
        ContainerStatus = $containerStatus
        Restarts = $restarts
    }
    
    if ($isHealthy) {
        $healthyPods += $podInfo
    }
    else {
        $unhealthyPods += $podInfo
    }
}

# Display healthy pods
if ($healthyPods.Count -gt 0) {
    Write-Host "`n  Healthy Pods ($($healthyPods.Count)):" -ForegroundColor Green
    foreach ($pod in $healthyPods) {
        Write-Host "    ✓ $($pod.Name) - Running (restarts: $($pod.Restarts))" -ForegroundColor Green
    }
}

# Display unhealthy pods
if ($unhealthyPods.Count -gt 0) {
    Write-Host "`n  Unhealthy Pods ($($unhealthyPods.Count)):" -ForegroundColor Red
    foreach ($pod in $unhealthyPods) {
        $reason = if ($pod.ContainerStatus -ne "Running") { $pod.ContainerStatus } else { "High restarts" }
        Write-Host "    ✗ $($pod.Name) - $($pod.Phase)/$($pod.ContainerStatus) (restarts: $($pod.Restarts))" -ForegroundColor Red
    }
}

# Resource Usage
Write-Host "`n--- RESOURCE USAGE ---" -ForegroundColor Yellow
try {
    $topOutput = kubectl top pods -n $Namespace --no-headers 2>$null
    if ($topOutput) {
        Write-Host "  Pod                          CPU    Memory"
        Write-Host "  ---                          ---    ------"
        foreach ($line in $topOutput) {
            Write-Host "  $line"
        }
    }
    else {
        Write-Host "  Metrics not available (metrics-server may not be installed)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Could not retrieve resource metrics" -ForegroundColor Yellow
}

# Events
if ($IncludeEvents) {
    Write-Host "`n--- RECENT EVENTS ---" -ForegroundColor Yellow
    $events = kubectl get events -n $Namespace --sort-by='.lastTimestamp' -o json 2>$null | ConvertFrom-Json
    
    if ($events.items) {
        $recentEvents = $events.items | Select-Object -Last 10
        foreach ($event in $recentEvents) {
            $type = $event.type
            $reason = $event.reason
            $message = $event.message
            $involved = $event.involvedObject.name
            
            $color = if ($type -eq "Warning") { "Yellow" } else { "White" }
            Write-Host "  [$type] $reason - $involved" -ForegroundColor $color
            Write-Host "    $message" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  No recent events" -ForegroundColor Gray
    }
}

# Logs from unhealthy pods
if ($IncludeLogs -and $unhealthyPods.Count -gt 0) {
    Write-Host "`n--- UNHEALTHY POD LOGS ---" -ForegroundColor Yellow
    foreach ($pod in $unhealthyPods) {
        Write-Host "`n  Logs for $($pod.Name):" -ForegroundColor White
        $logs = kubectl logs $pod.Name -n $Namespace --tail=10 2>$null
        if ($logs) {
            foreach ($line in $logs) {
                Write-Host "    $line" -ForegroundColor Gray
            }
        }
        else {
            # Try previous container
            $prevLogs = kubectl logs $pod.Name -n $Namespace --previous --tail=10 2>$null
            if ($prevLogs) {
                Write-Host "    (Previous container logs):" -ForegroundColor Yellow
                foreach ($line in $prevLogs) {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "    No logs available" -ForegroundColor Yellow
            }
        }
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "HEALTH SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalPods = $healthyPods.Count + $unhealthyPods.Count
$healthPercentage = [math]::Round(($healthyPods.Count / $totalPods) * 100, 1)

Write-Host "Total Pods: $totalPods"
Write-Host "Healthy: $($healthyPods.Count) ($healthPercentage%)"
Write-Host "Unhealthy: $($unhealthyPods.Count)"

if ($unhealthyPods.Count -eq 0) {
    Write-Host "`nOVERALL STATUS: HEALTHY" -ForegroundColor Green
    return $true
}
elseif ($unhealthyPods.Count -lt ($totalPods / 2)) {
    Write-Host "`nOVERALL STATUS: DEGRADED" -ForegroundColor Yellow
    Write-Host "Action Required: Investigate unhealthy pods"
    return $false
}
else {
    Write-Host "`nOVERALL STATUS: CRITICAL" -ForegroundColor Red
    Write-Host "Immediate Action Required!"
    return $false
}
