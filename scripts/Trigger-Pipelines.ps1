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

foreach ($workload in $workloads) {
    $pipelineName = "dmc-$workload"
    Write-Host "Triggering $pipelineName on branch main..."
    az pipelines run --name $pipelineName --branch main
}
