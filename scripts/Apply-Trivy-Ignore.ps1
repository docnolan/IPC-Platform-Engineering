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

$ignoreContent = @"
# SQLite Integer Overflow (RiskID: RR-001)
CVE-2025-7458
# Zlib Integer Overflow (RiskID: RR-002)
CVE-2023-45853
"@

foreach ($workload in $workloads) {
    $path = "docker/$workload/.trivyignore"
    Set-Content -Path $path -Value $ignoreContent
    Write-Host "Created $path" -ForegroundColor Green
}
