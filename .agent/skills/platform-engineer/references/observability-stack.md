# Observability Stack

Comprehensive guide for implementing observability in edge environments. Covers metrics, logging, tracing, and alerting with both self-hosted and SaaS options.

## Three Pillars of Observability

```
┌─────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY                            │
├───────────────────┬───────────────────┬─────────────────────┤
│      METRICS      │      LOGS         │      TRACES         │
│                   │                   │                     │
│  "What happened"  │  "Why it         │  "How requests      │
│  (quantitative)   │   happened"       │   flow"             │
│                   │  (qualitative)    │  (contextual)       │
│                   │                   │                     │
│  • CPU usage      │  • Error messages │  • Request path     │
│  • Request count  │  • Stack traces   │  • Latency breakdown│
│  • Latency p99    │  • Audit events   │  • Service deps     │
│  • Error rate     │  • Debug info     │  • Bottlenecks      │
│                   │                   │                     │
│  Prometheus       │  Loki             │  Jaeger             │
│  Datadog          │  ELK Stack        │  Zipkin             │
│  Azure Monitor    │  Azure Log        │  App Insights       │
│                   │  Analytics        │                     │
└───────────────────┴───────────────────┴─────────────────────┘
```

---

## Metrics Stack Options

### Prometheus (Self-Hosted)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus Stack                         │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Prometheus Server                    │   │
│  │  • Scrapes metrics from targets                      │   │
│  │  • Stores time-series data                           │   │
│  │  • Evaluates alerting rules                          │   │
│  └──────────────────────────────────────────────────────┘   │
│           │                         │                       │
│           ▼                         ▼                       │
│  ┌──────────────┐          ┌──────────────┐                │
│  │ Alertmanager │          │    Grafana   │                │
│  │ (Alerts)     │          │ (Dashboards) │                │
│  └──────────────┘          └──────────────┘                │
│           │                                                 │
│           ▼                                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Targets (Scrape Endpoints)              │   │
│  │  • Node Exporter (OS metrics)                        │   │
│  │  • kube-state-metrics (K8s objects)                  │   │
│  │  • Application /metrics endpoints                    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Installation (kube-prometheus-stack):**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi
```

**Resource Requirements (Edge):**
| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Prometheus | 200m | 512Mi | 10GB/week |
| Alertmanager | 50m | 64Mi | 100MB |
| Grafana | 100m | 128Mi | 1GB |
| Node Exporter | 50m | 32Mi | - |

**Best For:**
- Self-hosted, air-gapped environments
- Kubernetes-native metrics
- Cost-conscious deployments
- Custom metric collection

---

### Datadog (SaaS)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      Edge Cluster                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Datadog Agent                       │   │
│  │  • Collects metrics, logs, traces                    │   │
│  │  • Local aggregation                                 │   │
│  │  • Compressed upload                                 │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                    Datadog Cloud                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Metrics   │  │    Logs    │  │   APM      │            │
│  └────────────┘  └────────────┘  └────────────┘            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ Dashboards │  │   Alerts   │  │  Monitors  │            │
│  └────────────┘  └────────────┘  └────────────┘            │
└──────────────────────────────────────────────────────────────┘
```

**Installation:**
```bash
helm repo add datadog https://helm.datadoghq.com
helm install datadog datadog/datadog \
  --namespace datadog \
  --create-namespace \
  --set datadog.apiKey=${DD_API_KEY} \
  --set datadog.site='datadoghq.com' \
  --set datadog.logs.enabled=true \
  --set datadog.apm.enabled=true
```

**Best For:**
- Unified observability platform
- Multi-cloud/hybrid environments
- Teams without monitoring expertise
- Rich integration ecosystem

**Edge Considerations:**
- Requires internet connectivity
- Per-host pricing model
- Agent has ~100MB memory footprint

---

### Azure Monitor (Azure-Native)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      Edge Cluster                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Azure Monitor Agent                     │   │
│  │  • Container Insights (K8s metrics)                  │   │
│  │  • Custom metrics via SDK                            │   │
│  │  • Log collection                                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                         Azure                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Log Analytics                        │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐      │ │
│  │  │  Metrics   │  │    Logs    │  │   Tables   │      │ │
│  │  └────────────┘  └────────────┘  └────────────┘      │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Azure Monitor                        │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐      │ │
│  │  │ Workbooks  │  │   Alerts   │  │ Dashboards │      │ │
│  │  └────────────┘  └────────────┘  └────────────┘      │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

**Configuration (Arc-enabled):**
```bash
# Enable Container Insights on Arc cluster
az k8s-extension create \
  --name azuremonitor-containers \
  --cluster-name <your-arc-cluster-name> \
  --resource-group rg-ipc-platform-arc \
  --cluster-type connectedClusters \
  --extension-type Microsoft.AzureMonitor.Containers
```

**Best For:**
- Azure-centric organizations
- Arc-enabled Kubernetes
- Compliance requirements (Azure Gov)
- Existing Azure investment

---

## Logging Stack Options

### Loki (Prometheus-Compatible)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      Loki Stack                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Promtail                          │   │
│  │  • Discovers targets (pods, files)                   │   │
│  │  • Tails logs                                        │   │
│  │  • Adds labels                                       │   │
│  │  • Ships to Loki                                     │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                      Loki                            │   │
│  │  • Indexes labels (not full text)                    │   │
│  │  • Compresses chunks                                 │   │
│  │  • Object storage backend                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Grafana                           │   │
│  │  • LogQL queries                                     │   │
│  │  • Log exploration                                   │   │
│  │  • Correlation with metrics                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Resource Requirements:**
- Loki: 256Mi memory, local storage or S3
- Promtail: 64Mi memory per node
- Much lighter than ELK stack

**Best For:**
- Prometheus/Grafana users
- Resource-constrained edge
- Label-based log queries
- Cost-effective logging

---

### Azure Log Analytics

**Custom Table Schema:**
```kql
// IPCHealthMonitor_CL table structure
{
    "TimeGenerated": "datetime",
    "Computer_s": "string",
    "CPUUsage_d": "double",
    "MemoryUsage_d": "double",
    "DiskUsage_d": "double",
    "NetworkBytesIn_d": "double",
    "NetworkBytesOut_d": "double"
}
```

**Ingestion Methods:**
1. **Azure Monitor Agent** - OS and container logs
2. **Data Collection Rules** - Custom log ingestion
3. **HTTP Data Collector API** - Application metrics
4. **Log Analytics SDK** - Programmatic ingestion

**Best For:**
- Azure-native deployments
- Compliance (immutable, encrypted)
- Long-term retention
- KQL query language

---

## Tracing Options

### Jaeger

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                    Application Pod                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │   Application with OpenTelemetry SDK                 │   │
│  │   - Instrument code                                  │   │
│  │   - Create spans                                     │   │
│  │   - Export traces                                    │   │
│  └───────────────────────────┬──────────────────────────┘   │
│                              │                              │
└──────────────────────────────┼──────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                      Jaeger                                 │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │  Collector │──│   Storage  │──│   Query    │            │
│  │            │  │ (Cassandra/│  │   (UI)     │            │
│  │            │  │  Elastic)  │  │            │            │
│  └────────────┘  └────────────┘  └────────────┘            │
└──────────────────────────────────────────────────────────────┘
```

**When to Use Tracing:**
- Microservices architectures
- Debugging latency issues
- Understanding request flow
- Identifying bottlenecks

**Edge Consideration:**
- Often overkill for single-node edge
- Useful for edge-to-cloud request flows
- Consider sampling to reduce overhead

---

## Alerting Strategy

### Alert Severity Levels

| Level | Response Time | Examples |
|-------|---------------|----------|
| **P1 - Critical** | 15 minutes | System down, data loss risk |
| **P2 - High** | 1 hour | Degraded service, compliance risk |
| **P3 - Medium** | 4 hours | Performance degradation |
| **P4 - Low** | Next business day | Warning threshold |

### Essential Alerts for Edge

```yaml
# Node Health
- alert: NodeDown
  expr: up{job="node-exporter"} == 0
  for: 2m
  severity: critical

# Resource Exhaustion
- alert: HighMemoryUsage
  expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9
  for: 5m
  severity: warning

- alert: DiskSpaceLow
  expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes < 0.1
  for: 5m
  severity: critical

# Kubernetes
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  for: 5m
  severity: warning

- alert: DeploymentReplicasMismatch
  expr: kube_deployment_status_replicas_available != kube_deployment_spec_replicas
  for: 10m
  severity: warning

# Application
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
  for: 5m
  severity: warning

# GitOps
- alert: FluxSyncFailed
  expr: gotk_reconcile_condition{status="False",type="Ready"} == 1
  for: 10m
  severity: warning
```

---

## IPC Platform Observability Stack

### Recommended Configuration

```yaml
Metrics:
  Primary: Azure Monitor (Container Insights)
  Local: Prometheus (optional, for real-time)
  
Logging:
  Primary: Azure Log Analytics
  Retention: 90 days (compliance)
  
Tracing:
  Use: Only if debugging complex flows
  Tool: Azure App Insights or Jaeger
  
Dashboards:
  Cloud: Azure Workbooks
  Local: Grafana (optional)
  
Alerting:
  Primary: Azure Monitor Alerts
  Channels: Email, Teams, PagerDuty
```

### Custom Tables in Log Analytics

| Table | Source | Purpose |
|-------|--------|---------|
| `IPCHealthMonitor_CL` | health-monitor | System metrics |
| `IPCSecurityAudit_CL` | log-forwarder | Security events |
| `IPCAnomalyDetection_CL` | anomaly-detection | Anomaly alerts |
| `ContainerLog` | Container Insights | Pod logs |
| `KubeEvents` | Container Insights | K8s events |

### Dashboard Essentials

```
┌─────────────────────────────────────────────────────────────┐
│                  IPC Platform Dashboard                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Fleet Status│  │ Compliance  │  │   Alerts    │         │
│  │   7 / 7 ✓   │  │    98%      │  │     0       │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           CPU Usage (Last 24h)                      │   │
│  │  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁▂▃▄▅▆▇█▇▆▅▄▃▂▁                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Recent Events                             │   │
│  │  • [INFO] Deployment updated: health-monitor        │   │
│  │  • [WARN] High memory usage on node-1               │   │
│  │  • [INFO] GitOps sync completed                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```
