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
    "vision-simulator"
)

$project = "IPC-Platform-Engineering"
$orgUrl = "https://dev.azure.com/<your-org>"
$branch = "feature/golden-pipeline-rollout" # Files only exist here for now

foreach ($workload in $workloads) {
    $pipelineName = "dmc-$workload"
    $yamlPath = "docker/$workload/azure-pipelines.yml"
    
    Write-Host "Creating pipeline: $pipelineName..."
    
    # Check if pipeline exists first to avoid errors
    $exists = az pipelines show --name $pipelineName --project $project --organization $orgUrl 2>$null
    
    if (-not $exists) {
        az pipelines create `
            --name $pipelineName `
            --project $project `
            --organization $orgUrl `
            --repository $project `
            --repository-type tfsgit `
            --branch $branch `
            --yaml-path $yamlPath `
            --skip-first-run
            
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully created $pipelineName" -ForegroundColor Green
        }
        else {
            Write-Host "Failed to create $pipelineName" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Pipeline $pipelineName already exists. Skipping." -ForegroundColor Yellow
    }
}
