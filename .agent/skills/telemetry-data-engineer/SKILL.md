---
name: telemetry-data-engineer
description: |
  Use this skill to work with Log Analytics, KQL queries, and dashboards.
  Activated when: KQL queries need development, dashboards need creation,
  telemetry patterns need analysis, or compliance evidence queries are required.
  The data insight specialist.
license: MIT
metadata:
  author: <your-org>
  version: "1.0"
  area: Observability
  pillar: Data
---

# Telemetry Data Engineer

## Role

Designs and implements KQL queries for Log Analytics, builds Azure dashboards and workbooks, analyzes telemetry patterns, and creates alerting rules. Transforms raw operational data into actionable insights for monitoring, compliance, and business intelligence.

## Trigger Conditions

- KQL query development or optimization requested
- `fleet-conductor` requests data analysis
- Request contains: "kql", "query", "dashboard", "workbook", "alert", "log analytics", "telemetry", "metrics"
- Need to investigate historical data patterns
- Compliance evidence queries needed
- Performance trending or capacity planning
- Alert rule creation or modification

## Inputs

- Query requirements or question to answer
- Target Log Analytics table(s)
- Time range for analysis
- Output format needs (visualization, export)

## Outputs

- KQL queries (tested and optimized)
- Azure Workbook definitions
- Dashboard configurations
- Alert rule definitions
- Data analysis reports

---

## Phase 1: Data Discovery

When telemetry work is triggered:

1. **Identify data sources**:

   | Table | Source | Contents |
   |-------|--------|----------|
   | `IPCHealthMonitor_CL` | health-monitor | CPU, memory, disk, network metrics |
   | `IPCSecurityAudit_CL` | log-forwarder | Windows Security events |
   | `IPCAnomalyDetection_CL` | anomaly-detection | Statistical anomaly alerts |
   | `Heartbeat` | Azure Monitor Agent | Agent health |
   | `ContainerLog` | Container Insights | Pod stdout/stderr |
   | `KubeEvents` | Container Insights | Kubernetes events |
   | `Perf` | Container Insights | Container performance |

2. **Understand table schema**:
   ```kql
   // Get table schema
   IPCHealthMonitor_CL
   | getschema
   
   // Sample data
   IPCHealthMonitor_CL
   | take 10
   
   // Time range coverage
   IPCHealthMonitor_CL
   | summarize MinTime=min(TimeGenerated), MaxTime=max(TimeGenerated)
   ```

3. **Assess data quality**:
   ```kql
   // Check for gaps
   IPCHealthMonitor_CL
   | summarize count() by bin(TimeGenerated, 1h)
   | order by TimeGenerated asc
   
   // Check for nulls
   IPCHealthMonitor_CL
   | summarize 
       TotalRows=count(),
       NullCPU=countif(isnull(CPUUsage_d)),
       NullMemory=countif(isnull(MemoryUsage_d))
   ```

4. **REPORT** data discovery:
   ```
   DATA DISCOVERY
   ==============
   Request: [what's needed]
   
   Relevant Tables:
   - [table]: [row count], [time range]
   
   Schema:
   - [column]: [type] - [description]
   
   Data Quality:
   - Coverage: [time range with data]
   - Gaps: [any gaps identified]
   - Freshness: [last data timestamp]
   
   Proceed with query development? [Y/N]
   ```

## Phase 2: Query Development

Build KQL queries following best practices:

1. **Standard query structure**:
   ```kql
   // 1. Start with table
   TableName
   // 2. Time filter FIRST (most important for performance)
   | where TimeGenerated > ago(24h)
   // 3. Additional filters
   | where Column == "value"
   // 4. Transformations
   | extend NewColumn = expression
   // 5. Aggregations
   | summarize Count=count() by bin(TimeGenerated, 1h)
   // 6. Sorting
   | order by TimeGenerated desc
   // 7. Projection (select columns)
   | project TimeGenerated, Count
   ```

2. **Query patterns by use case**:

   **Health Monitoring:**
   ```kql
   // Current system health
   IPCHealthMonitor_CL
   | where TimeGenerated > ago(5m)
   | summarize 
       AvgCPU=avg(CPUUsage_d),
       AvgMemory=avg(MemoryUsage_d),
       AvgDisk=avg(DiskUsage_d)
       by Computer_s
   ```

   **Security Audit:**
   ```kql
   // Failed logon attempts (last 24h)
   IPCSecurityAudit_CL
   | where TimeGenerated > ago(24h)
   | where EventID_d == 4625
   | summarize FailedAttempts=count() by Account_s, Computer_s
   | order by FailedAttempts desc
   ```

   **Anomaly Detection:**
   ```kql
   // Recent anomalies
   IPCAnomalyDetection_CL
   | where TimeGenerated > ago(1h)
   | where IsAnomaly_b == true
   | project TimeGenerated, Metric_s, Value_d, ZScore_d
   ```

   **Trend Analysis:**
   ```kql
   // CPU trend over time
   IPCHealthMonitor_CL
   | where TimeGenerated > ago(7d)
   | summarize AvgCPU=avg(CPUUsage_d) by bin(TimeGenerated, 1h)
   | render timechart
   ```

3. **PAUSE** and present query:
   ```
   QUERY DEVELOPMENT
   =================
   Purpose: [what the query answers]
   
   Query:
   ```kql
   [the KQL query]
   ```
   
   Expected Output:
   - Columns: [list]
   - Rows: [estimated]
   - Visualization: [if applicable]
   
   Test query in Log Analytics? [Y/N]
   ```

## Phase 3: Validation and Testing

Before finalizing:

1. **Execute and validate**:
   ```powershell
   # Run query via Azure CLI
   az monitor log-analytics query `
     --workspace $workspaceId `
     --analytics-query "[KQL query]" `
     --timespan "PT24H"
   ```

2. **Check performance**:
   - Query should complete in < 30 seconds
   - Avoid full table scans
   - Use time filters early
   - Limit result sets appropriately

3. **Validate results**:
   - Do results make sense?
   - Are there unexpected nulls?
   - Is the time range correct?
   - Do aggregations match expectations?

4. **Optimize if needed**:
   ```kql
   // Use let statements for complex queries
   let StartTime = ago(24h);
   let EndTime = now();
   let Threshold = 80;
   
   IPCHealthMonitor_CL
   | where TimeGenerated between (StartTime .. EndTime)
   | where CPUUsage_d > Threshold
   ```

## Phase 4: Deployment

Deploy queries to their destinations:

### Save to Workbook

```json
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "[KQL query here]",
        "size": 0,
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "timechart"
      }
    }
  ]
}
```

### Create Alert Rule

```powershell
# Create alert rule
az monitor scheduled-query create `
  --name "High CPU Alert" `
  --resource-group rg-ipc-platform-monitoring `
  --scopes "/subscriptions/.../workspaces/<your-workspace-name>" `
  --condition "count > 0" `
  --condition-query "IPCHealthMonitor_CL | where CPUUsage_d > 90" `
  --evaluation-frequency 5m `
  --window-size 5m `
  --severity 2
```

### Document Query

```
QUERY DEPLOYMENT
================
Query Name: [descriptive name]
Purpose: [what it answers]

Query:
```kql
[final query]
```

Deployed To:
- [ ] Workbook: [name]
- [ ] Alert Rule: [name]
- [ ] Saved Query: [name]

Documentation:
- Added to: [wiki page]
```

---

## KQL Quick Reference

### Common Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `ago()` | Relative time | `ago(24h)`, `ago(7d)` |
| `between()` | Time range | `between(ago(7d) .. ago(1d))` |
| `bin()` | Time bucketing | `bin(TimeGenerated, 1h)` |
| `count()` | Count rows | `summarize count()` |
| `avg()`, `sum()`, `min()`, `max()` | Aggregations | `summarize avg(CPUUsage_d)` |
| `percentile()` | Percentiles | `percentile(Duration, 95)` |
| `extend` | Add column | `extend Status = iff(Value > 80, "High", "Normal")` |
| `project` | Select columns | `project TimeGenerated, Value` |
| `where` | Filter rows | `where Status == "Error"` |
| `summarize` | Aggregate | `summarize count() by Computer` |
| `order by` | Sort | `order by TimeGenerated desc` |
| `take` / `limit` | Limit rows | `take 100` |
| `render` | Visualize | `render timechart` |

### String Functions

```kql
| where Message contains "error"
| where Message startswith "Failed"
| where Message matches regex "Error.*code"
| extend ShortMessage = substring(Message, 0, 50)
```

### Conditional Logic

```kql
| extend Severity = case(
    Value > 90, "Critical",
    Value > 75, "Warning",
    "Normal")
    
| extend Status = iff(IsError == true, "Error", "OK")
```

### Joins

```kql
Table1
| join kind=inner (Table2) on CommonColumn
```

---

## IPC Platform Tables Schema

### IPCHealthMonitor_CL

| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | Timestamp |
| Computer_s | string | Hostname |
| CPUUsage_d | double | CPU percentage |
| MemoryUsage_d | double | Memory percentage |
| DiskUsage_d | double | Disk percentage |
| NetworkBytesIn_d | double | Network bytes received |
| NetworkBytesOut_d | double | Network bytes sent |

### IPCSecurityAudit_CL

| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | Event timestamp |
| Computer_s | string | Hostname |
| EventID_d | double | Windows Event ID |
| Account_s | string | Account name |
| LogonType_d | double | Logon type code |
| Message_s | string | Event message |

### IPCAnomalyDetection_CL

| Column | Type | Description |
|--------|------|-------------|
| TimeGenerated | datetime | Detection timestamp |
| Metric_s | string | Metric name |
| Value_d | double | Metric value |
| ZScore_d | double | Z-score |
| Threshold_d | double | Anomaly threshold |
| IsAnomaly_b | boolean | Is anomaly flag |

---

## Tool Access

| Tool | Purpose |
|------|---------|
| Azure Portal | Log Analytics query editor |
| `az monitor` | CLI query execution |
| PowerShell | Automation |
| Azure Workbooks | Visualization |

## Handoff Rules

| Situation | Action |
|-----------|--------|
| Data not being collected | Route to `site-reliability-engineer` |
| Compliance evidence needed | Coordinate with `compliance-auditor` |
| Dashboard documentation | Route to `knowledge-curator` |
| Alert requires code fix | Route to `platform-engineer` |

## Constraints

- **Always filter by time first** — Performance critical
- **Always test before deploying** — Validate results
- **Always document queries** — Others need to understand
- **Never query without time bounds** — Can timeout or cost $$$
- **Never expose sensitive data** — Mask PII in outputs
- **Optimize expensive queries** — Monitor query costs
