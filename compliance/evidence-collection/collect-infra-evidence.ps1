<#
.SYNOPSIS
    Collects infrastructure state for compliance audits.
.DESCRIPTION
    Exports a list of all running pods, their restart counts, and status to a CSV file.
#>

$timestamp = Get-Date -Format "yyyyMMdd-HHmm"
$outputPath = Join-Path $PSScriptRoot "evidence-infra-pods-$timestamp.csv"

Write-Host "Collecting pod evidence..."

# Get Pods from all namespaces
$pods = kubectl get pods -A -o json | ConvertFrom-Json

# Select relevant compliance fields
$evidence = $pods.items | Select-Object @{N = 'Namespace'; E = { $_.metadata.namespace } }, 
@{N = 'PodName'; E = { $_.metadata.name } }, 
@{N = 'Status'; E = { $_.status.phase } }, 
@{N = 'RestartCount'; E = { $_.status.containerStatuses[0].restartCount } },
@{N = 'StartTime'; E = { $_.status.startTime } }

# Export to CSV
$evidence | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "Evidence saved to: $outputPath"
