# KQL Query Patterns

Reference document for Kusto Query Language (KQL) patterns used with IPC Platform telemetry.

## Log Analytics Tables

### Custom Tables (IPC Platform)

| Table | Source | Schema |
|-------|--------|--------|
| `IPCHealthMonitor_CL` | health-monitor workload | Computer_s, CPUUsage_d, MemoryUsage_d, DiskUsage_d, NetworkBytes_d, TimeGenerated |
| `IPCSecurityAudit_CL` | log-forwarder workload | Computer_s, EventID_d, Account_s, LogonType_d, Message_s, TimeGenerated |
| `IPCAnomalyDetection_CL` | anomaly-detection workload | Metric_s, Value_d, ZScore_d, Threshold_d, IsAnomaly_b, TimeGenerated |

### Built-in Tables

| Table | Source | Use Case |
|-------|--------|----------|
| `Heartbeat` | Azure Monitor Agent | Agent connectivity |
| `ContainerLog` | Container Insights | Container stdout/stderr |
| `KubeEvents` | Container Insights | Kubernetes events |
| `Perf` | Azure Monitor Agent | Performance counters |

## Query Structure Best Practices

### Standard Query Pattern

```kql
TableName                           // 1. Start with table
| where TimeGenerated > ago(24h)    // 2. Time filter FIRST (performance)
| where <additional filters>        // 3. Other filters
| extend <calculations>             // 4. Add calculated columns
| summarize <aggregations>          // 5. Aggregate data
| project <columns>                 // 6. Select final columns
| order by <column> desc            // 7. Sort results
| take 100                          // 8. Limit rows if needed
```

### Time Filters (Always First!)

```kql
// Relative time
| where TimeGenerated > ago(1h)     // Last hour
| where TimeGenerated > ago(24h)    // Last day
| where TimeGenerated > ago(7d)     // Last week
| where TimeGenerated > ago(30d)    // Last month

// Absolute time
| where TimeGenerated >= datetime(2025-01-01)
| where TimeGenerated between (datetime(2025-01-01) .. datetime(2025-01-31))

// Time binning for trends
| summarize Count = count() by bin(TimeGenerated, 5m)   // 5-minute buckets
| summarize Count = count() by bin(TimeGenerated, 1h)   // Hourly buckets
| summarize Count = count() by bin(TimeGenerated, 1d)   // Daily buckets
```

## Common Query Patterns

### Health Monitoring Queries

#### Current System Health
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(5m)
| summarize 
    AvgCPU = avg(todouble(CPUUsage_d)),
    AvgMemory = avg(todouble(MemoryUsage_d)),
    AvgDisk = avg(todouble(DiskUsage_d))
  by Computer_s
| project Computer_s, 
    CPU = round(AvgCPU, 1),
    Memory = round(AvgMemory, 1),
    Disk = round(AvgDisk, 1)
```

#### CPU Trend Over Time
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(24h)
| extend CPUPercent = todouble(CPUUsage_d)
| summarize 
    AvgCPU = avg(CPUPercent),
    MaxCPU = max(CPUPercent),
    MinCPU = min(CPUPercent)
  by bin(TimeGenerated, 15m)
| render timechart
```

#### High Resource Usage Alerts
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(1h)
| where todouble(CPUUsage_d) > 80 or todouble(MemoryUsage_d) > 85
| project TimeGenerated, Computer_s, 
    CPU = round(todouble(CPUUsage_d), 1),
    Memory = round(todouble(MemoryUsage_d), 1)
| order by TimeGenerated desc
```

### Security Audit Queries

#### Event Summary by Type
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| summarize Count = count() by EventID_d
| extend EventName = case(
    EventID_d == 4624, "Successful Logon",
    EventID_d == 4625, "Failed Logon",
    EventID_d == 4634, "Logoff",
    EventID_d == 4672, "Special Privileges",
    EventID_d == 4720, "Account Created",
    EventID_d == 4722, "Account Enabled",
    EventID_d == 4725, "Account Disabled",
    EventID_d == 4726, "Account Deleted",
    strcat("Event ", tostring(EventID_d)))
| project EventID_d, EventName, Count
| order by Count desc
```

#### Failed Logon Attempts
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| where EventID_d == 4625
| summarize 
    FailedAttempts = count(),
    FirstAttempt = min(TimeGenerated),
    LastAttempt = max(TimeGenerated)
  by Account_s
| where FailedAttempts > 3
| order by FailedAttempts desc
```

#### Privileged Account Usage
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(24h)
| where EventID_d == 4672  // Special privileges assigned
| summarize UsageCount = count() by Account_s, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

#### Compliance Evidence (90-day retention)
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(90d)
| summarize 
    TotalEvents = count(),
    DaysWithLogs = dcount(bin(TimeGenerated, 1d))
| extend RetentionDays = 90, CoveragePercent = round(DaysWithLogs * 100.0 / 90, 1)
```

### Anomaly Detection Queries

#### Recent Anomalies
```kql
IPCAnomalyDetection_CL
| where TimeGenerated > ago(24h)
| where IsAnomaly_b == true
| project TimeGenerated, Metric_s, Value_d, ZScore_d
| order by TimeGenerated desc
```

#### Anomaly Frequency by Metric
```kql
IPCAnomalyDetection_CL
| where TimeGenerated > ago(7d)
| where IsAnomaly_b == true
| summarize AnomalyCount = count() by Metric_s
| order by AnomalyCount desc
```

### Data Quality Queries

#### Data Freshness Check
```kql
union 
    (IPCHealthMonitor_CL | summarize LastUpdate = max(TimeGenerated) | extend Table = "IPCHealthMonitor_CL"),
    (IPCSecurityAudit_CL | summarize LastUpdate = max(TimeGenerated) | extend Table = "IPCSecurityAudit_CL")
| extend MinutesSinceUpdate = datetime_diff('minute', now(), LastUpdate)
| extend Status = iff(MinutesSinceUpdate > 15, "STALE", "FRESH")
| project Table, LastUpdate, MinutesSinceUpdate, Status
```

#### Data Volume Trend
```kql
union 
    (IPCHealthMonitor_CL | extend Table = "Health"),
    (IPCSecurityAudit_CL | extend Table = "Security")
| where TimeGenerated > ago(7d)
| summarize RecordCount = count() by Table, bin(TimeGenerated, 1d)
| render columnchart
```

## Visualization Patterns

### Time Charts
```kql
// Line chart for trends
| render timechart

// With specific title
| render timechart with (title="CPU Usage Over Time")
```

### Bar Charts
```kql
// Column chart for comparisons
| render columnchart

// Bar chart (horizontal)
| render barchart
```

### Pie Charts
```kql
// Distribution visualization
| render piechart
```

### Tables
```kql
// Formatted table (default)
| project Column1, Column2, Column3
```

## Alert Query Patterns

### High CPU Alert
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(5m)
| where todouble(CPUUsage_d) > 90
| summarize AlertCount = count() by Computer_s
| where AlertCount > 0
```

### No Data Alert (Heartbeat)
```kql
IPCHealthMonitor_CL
| where TimeGenerated > ago(15m)
| summarize LastSeen = max(TimeGenerated) by Computer_s
| where LastSeen < ago(10m)
```

### Security Alert (Multiple Failed Logons)
```kql
IPCSecurityAudit_CL
| where TimeGenerated > ago(15m)
| where EventID_d == 4625
| summarize FailedAttempts = count() by Account_s
| where FailedAttempts >= 5
```

## Performance Optimization

### Do's
- Always filter by time first
- Use `project` to select only needed columns
- Use `summarize` to aggregate early
- Use `take` or `limit` during development
- Use `has` instead of `contains` for string matching (faster)

### Don'ts
- Avoid `select *` patterns
- Avoid expensive operations without time filters
- Avoid `matches regex` when simpler operators work
- Avoid multiple `parse` operations on same field

### Query Cost Estimation
```kql
// Check data volume before running expensive query
IPCHealthMonitor_CL
| where TimeGenerated > ago(30d)
| summarize RecordCount = count(), DataSizeMB = sum(estimate_data_size(*)) / 1024 / 1024
```

## Useful Functions

### String Functions
```kql
| where Computer_s has "Factory"           // Contains (fast)
| where Computer_s startswith "DMC"        // Starts with
| where Computer_s matches regex "DMC-.*"  // Regex (slow)
| extend ShortName = substring(Computer_s, 0, 10)
```

### Numeric Functions
```kql
| extend RoundedValue = round(Value_d, 2)
| extend Percentage = Value_d * 100
| extend AbsoluteValue = abs(Value_d)
```

### Date/Time Functions
```kql
| extend Hour = datetime_part("hour", TimeGenerated)
| extend DayOfWeek = dayofweek(TimeGenerated)
| extend DateOnly = startofday(TimeGenerated)
```

### Conditional Logic
```kql
| extend Status = iff(Value_d > 80, "High", "Normal")
| extend Category = case(
    Value_d > 90, "Critical",
    Value_d > 70, "Warning",
    "Normal")
```
