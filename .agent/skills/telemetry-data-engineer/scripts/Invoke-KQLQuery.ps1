<#
.SYNOPSIS
    Executes KQL queries against Azure Log Analytics workspace.

.DESCRIPTION
    Runs KQL queries via Azure CLI and formats results for analysis.
    Supports common IPC Platform queries and custom queries.

.PARAMETER WorkspaceId
    Log Analytics workspace ID (default: IPC Platform workspace).

.PARAMETER Query
    KQL query to execute.

.PARAMETER QueryName
    Name of a predefined query to run (alternative to -Query).

.PARAMETER Timespan
    ISO 8601 duration for query timespan (default: P1D = 1 day).

.PARAMETER OutputFormat
    Output format: Table, Json, or Csv (default: Table).

.EXAMPLE
    .\Invoke-KQLQuery.ps1 -QueryName "HealthSummary"

.EXAMPLE
    .\Invoke-KQLQuery.ps1 -Query "IPCHealthMonitor_CL | take 10"

.EXAMPLE
    .\Invoke-KQLQuery.ps1 -QueryName "SecurityEvents" -Timespan "P7D" -OutputFormat Csv
#>

param(
    [string]$WorkspaceId = "<your-workspace-id>",
    
    [Parameter(ParameterSetName = "Custom")]
    [string]$Query,
    
    [Parameter(ParameterSetName = "Predefined")]
    [ValidateSet("HealthSummary", "SecurityEvents", "AnomalyAlerts", "DataFreshness", "CPUTrend", "MemoryTrend", "FailedLogons")]
    [string]$QueryName,
    
    [string]$Timespan = "P1D",
    
    [ValidateSet("Table", "Json", "Csv")]
    [string]$OutputFormat = "Table"
)

# Predefined queries
$PredefinedQueries = @{
    "HealthSummary" = @"
IPCHealthMonitor_CL
| where TimeGenerated > ago(1h)
| summarize 
    AvgCPU = avg(todouble(CPUUsage_d)),
    AvgMemory = avg(todouble(MemoryUsage_d)),
    MaxCPU = max(todouble(CPUUsage_d)),
    MaxMemory = max(todouble(MemoryUsage_d)),
    RecordCount = count()
  by Computer_s
| project Computer_s, AvgCPU, AvgMemory, MaxCPU, MaxMemory, RecordCount
"@

    "SecurityEvents" = @"
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| summarize EventCount = count() by EventID_d, bin(TimeGenerated, 1h)
| order by TimeGenerated desc, EventCount desc
"@

    "AnomalyAlerts" = @"
IPCAnomalyDetection_CL
| where TimeGenerated > ago(24h)
| project TimeGenerated, Metric_s, Value_d, ZScore_d, Threshold_d
| order by TimeGenerated desc
"@

    "DataFreshness" = @"
union 
    (IPCHealthMonitor_CL | summarize LastUpdate = max(TimeGenerated) | extend Table = "IPCHealthMonitor_CL"),
    (IPCSecurityAudit_CL | summarize LastUpdate = max(TimeGenerated) | extend Table = "IPCSecurityAudit_CL"),
    (IPCAnomalyDetection_CL | summarize LastUpdate = max(TimeGenerated) | extend Table = "IPCAnomalyDetection_CL")
| project Table, LastUpdate, AgeMinutes = datetime_diff('minute', now(), LastUpdate)
| order by AgeMinutes asc
"@

    "CPUTrend" = @"
IPCHealthMonitor_CL
| where TimeGenerated > ago(24h)
| extend CPUPercent = todouble(CPUUsage_d)
| summarize AvgCPU = avg(CPUPercent), MaxCPU = max(CPUPercent) by bin(TimeGenerated, 15m)
| order by TimeGenerated asc
"@

    "MemoryTrend" = @"
IPCHealthMonitor_CL
| where TimeGenerated > ago(24h)
| extend MemoryPercent = todouble(MemoryUsage_d)
| summarize AvgMemory = avg(MemoryPercent), MaxMemory = max(MemoryPercent) by bin(TimeGenerated, 15m)
| order by TimeGenerated asc
"@

    "FailedLogons" = @"
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| where EventID_d == 4625
| summarize FailedAttempts = count() by Account_s, bin(TimeGenerated, 1h)
| order by FailedAttempts desc
"@
}

Write-Host "`nKQL QUERY EXECUTION" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host "Workspace: $WorkspaceId"
Write-Host "Timespan: $Timespan`n"

# Determine query to run
$QueryToRun = ""
if ($QueryName) {
    if ($PredefinedQueries.ContainsKey($QueryName)) {
        $QueryToRun = $PredefinedQueries[$QueryName]
        Write-Host "Query: $QueryName (predefined)" -ForegroundColor Yellow
    }
    else {
        Write-Host "ERROR: Unknown predefined query: $QueryName" -ForegroundColor Red
        return
    }
}
elseif ($Query) {
    $QueryToRun = $Query
    Write-Host "Query: Custom" -ForegroundColor Yellow
}
else {
    Write-Host "ERROR: Specify either -Query or -QueryName" -ForegroundColor Red
    Write-Host "`nAvailable predefined queries:"
    $PredefinedQueries.Keys | ForEach-Object { Write-Host "  - $_" }
    return
}

Write-Host "`nExecuting query..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
Write-Host $QueryToRun -ForegroundColor Gray
Write-Host "----------------------------------------`n"

# Check Azure CLI
$azAvailable = Get-Command az -ErrorAction SilentlyContinue
if (-not $azAvailable) {
    Write-Host "ERROR: Azure CLI not found." -ForegroundColor Red
    return
}

# Execute query
try {
    $startTime = Get-Date
    
    $result = az monitor log-analytics query `
        --workspace $WorkspaceId `
        --analytics-query $QueryToRun `
        --timespan $Timespan `
        2>$null
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    if (-not $result) {
        Write-Host "ERROR: Query returned no results or failed." -ForegroundColor Red
        Write-Host "Check workspace ID and query syntax." -ForegroundColor Yellow
        return
    }
    
    $data = $result | ConvertFrom-Json
    
    Write-Host "Query completed in $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
    Write-Host "Rows returned: $($data.Count)`n" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Query execution failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

# Output results
switch ($OutputFormat) {
    "Table" {
        if ($data.Count -eq 0) {
            Write-Host "No data returned." -ForegroundColor Yellow
        }
        else {
            $data | Format-Table -AutoSize
        }
    }
    "Json" {
        $data | ConvertTo-Json -Depth 10
    }
    "Csv" {
        $data | ConvertTo-Csv -NoTypeInformation
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "QUERY SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Status: Success"
Write-Host "Rows: $($data.Count)"
Write-Host "Duration: $([math]::Round($duration, 2))s"

if ($data.Count -gt 0) {
    Write-Host "`nColumns: $($data[0].PSObject.Properties.Name -join ', ')"
}

return $data
