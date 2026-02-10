[CmdletBinding()]
param()

$workloads = @(
    "anomaly-detection",
    "ev-battery-simulator",
    "health-monitor",
    "log-forwarder",
    "motion-gateway",
    "motion-simulator",
    "opcua-simulator",
    "test-data-collector",
    "vision-simulator",
    "opcua-gateway"
)

foreach ($workload in $workloads) {
    $pipelineFile = "docker/$workload/azure-pipelines.yml"
    $content = Get-Content -Path $pipelineFile -Raw
    
    # Check if we already have branch restrictions
    if ($content -notmatch "branches:") {
        # Indent the existing paths logic
        $content = $content -replace "trigger:`r`n  paths:", "trigger:`r`n  branches:`r`n    include:`r`n      - main`r`n  paths:"
        
        Set-Content -Path $pipelineFile -Value $content
        Write-Host "Updated triggers for $workload" -ForegroundColor Green
    }
    else {
        Write-Host "Triggers already restricted for $workload" -ForegroundColor Yellow
    }
}
