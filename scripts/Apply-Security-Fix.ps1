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
    $dockerfile = "docker/$workload/Dockerfile"
    $content = Get-Content -Path $dockerfile -Raw
    
    # 1. Pin Base Image
    $content = $content -replace "FROM python:3.11-slim", "FROM python:3.11-slim-bookworm"
    
    # 2. Add System Upgrades (if not present)
    if ($content -notmatch "apt-get upgrade") {
        $upgradeCmd = "`n# Upgrade system packages to fix vulnerabilities (e.g. CVE-2025-15467)`nRUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*`n"
        # Insert after WORKDIR /app
        $content = $content -replace "WORKDIR /app", "WORKDIR /app$upgradeCmd"
    }
    
    Set-Content -Path $dockerfile -Value $content
    Write-Host "Patched $dockerfile" -ForegroundColor Green
}
