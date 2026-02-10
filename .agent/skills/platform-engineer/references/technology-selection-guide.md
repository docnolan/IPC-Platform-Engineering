# Technology Selection Guide

Decision framework for selecting technologies in edge platform engineering. Use this guide when evaluating options for orchestration, storage, observability, and other platform components.

## Selection Framework

### Core Criteria

| Factor | Weight | Edge Considerations |
|--------|--------|---------------------|
| **Resource Footprint** | Critical | Edge nodes have limited CPU, memory, storage |
| **Offline Capability** | Critical | Network connectivity is unreliable |
| **Operational Simplicity** | High | Remote management, limited on-site expertise |
| **Security Posture** | High | Edge is physically accessible, compliance requirements |
| **Maturity & Support** | High | Production stability, community/vendor support |
| **Cost** | Medium | Licensing, infrastructure, operational overhead |
| **Portability** | Medium | Avoid vendor lock-in, multi-cloud strategy |
| **Team Expertise** | Medium | Learning curve, existing skills |

### Decision Matrix Template

When evaluating options, score each on 1-5 scale:

```
| Criteria              | Option A | Option B | Option C |
|-----------------------|----------|----------|----------|
| Resource Footprint    |    ?     |    ?     |    ?     |
| Offline Capability    |    ?     |    ?     |    ?     |
| Operational Simplicity|    ?     |    ?     |    ?     |
| Security Posture      |    ?     |    ?     |    ?     |
| Maturity & Support    |    ?     |    ?     |    ?     |
| Cost                  |    ?     |    ?     |    ?     |
| Portability           |    ?     |    ?     |    ?     |
| Team Expertise        |    ?     |    ?     |    ?     |
|-----------------------|----------|----------|----------|
| WEIGHTED TOTAL        |    ?     |    ?     |    ?     |
```

---

## Container Orchestration

### Options Comparison

| Platform | Best For | Resource Footprint | Complexity |
|----------|----------|-------------------|------------|
| **K3s** | Resource-constrained edge | ~512MB RAM | Low |
| **AKS Edge Essentials** | Windows + Azure integration | ~2GB RAM | Medium |
| **MicroK8s** | Ubuntu edge, snap ecosystem | ~1GB RAM | Low |
| **K0s** | Minimal Kubernetes | ~512MB RAM | Low |
| **Full Kubernetes** | Large edge clusters | ~4GB+ RAM | High |
| **Docker Swarm** | Simple container orchestration | ~256MB RAM | Very Low |
| **Nomad** | Mixed workloads (VMs + containers) | ~256MB RAM | Medium |

### Recommendation by Scenario

| Scenario | Recommended | Rationale |
|----------|-------------|-----------|
| Windows IoT + Azure | AKS Edge Essentials | Native Arc integration, Windows support |
| Linux edge, minimal | K3s or K0s | Smallest footprint, CNCF conformant |
| Ubuntu edge | MicroK8s | Snap updates, canonical support |
| Mixed VM + container | Nomad | Better VM support than K8s |
| Air-gapped edge | K3s | Full offline operation |
| Multi-cluster federation | K3s + Rancher | Centralized management |

### IPC Platform Choice: AKS Edge Essentials

**Rationale:**
- Windows IoT Enterprise LTSC base requirement
- Native Azure Arc integration for hybrid management
- Workload Identity Federation for zero-secret auth
- Microsoft support for industrial scenarios
- GitOps ready with Flux

**Trade-offs Accepted:**
- Higher resource footprint than K3s
- Azure dependency (acceptable for target customers)
- Windows-specific operational model

---

## Edge-to-Cloud Connectivity

### Options Comparison

| Platform | Provider | Best For | Offline Support |
|----------|----------|----------|-----------------|
| **Azure Arc** | Microsoft | Azure-centric hybrid | Yes (local ops) |
| **Anthos** | Google | GCP-centric hybrid | Yes (local ops) |
| **EKS Anywhere** | Amazon | AWS-centric hybrid | Yes (local ops) |
| **Rancher** | SUSE | Multi-cloud, vendor neutral | Yes |
| **OpenShift** | Red Hat | Enterprise, regulated | Yes |

### Recommendation by Cloud Strategy

| Strategy | Recommended | Notes |
|----------|-------------|-------|
| Azure primary | Azure Arc | Native integration, best tooling |
| GCP primary | Anthos | Fleet management, Config Sync |
| AWS primary | EKS Anywhere | Consistent EKS experience |
| Multi-cloud | Rancher or vendor-neutral GitOps | Avoid lock-in |
| Air-gapped | Any with local control plane | Rancher preferred |

---

## Storage Solutions

### Options Comparison

| Solution | Type | Best For | Complexity |
|----------|------|----------|------------|
| **Local PV** | Local | Single-node, simple | Very Low |
| **Longhorn** | Distributed | K8s-native, small clusters | Low |
| **Rook-Ceph** | Distributed | Large clusters, enterprise | High |
| **Robin.io** | Distributed | Stateful apps, snapshots | Medium |
| **OpenEBS** | Distributed | K8s-native, multiple engines | Medium |
| **Azure Blob (CSI)** | Cloud | Cloud-connected workloads | Low |

### Recommendation by Scenario

| Scenario | Recommended | Rationale |
|----------|-------------|-----------|
| Single-node edge | Local PV | Simplest, no overhead |
| 3+ node cluster | Longhorn | K8s-native, lightweight |
| High availability required | Rook-Ceph or Robin.io | Replication, failover |
| Stateful databases | Robin.io | Application-aware snapshots |
| Cloud-connected | Azure Blob CSI | Offload to cloud storage |

---

## Observability Stack

### Options Comparison

| Component | Options | Edge Considerations |
|-----------|---------|---------------------|
| **Metrics** | Prometheus, Datadog, Azure Monitor | Prometheus is self-hosted; SaaS needs connectivity |
| **Logging** | Loki, ELK, Azure Log Analytics | Loki is lightweight; ELK is heavy |
| **Tracing** | Jaeger, Zipkin, Azure App Insights | Jaeger is CNCF standard |
| **Dashboards** | Grafana, Azure Workbooks, Datadog | Grafana is universal |

### Recommended Stacks

**Self-Hosted Edge (Air-Gapped Capable):**
```
Metrics:    Prometheus + node_exporter
Logging:    Loki + Promtail
Tracing:    Jaeger (if needed)
Dashboards: Grafana
Alerting:   Alertmanager
```

**Azure-Connected Edge:**
```
Metrics:    Azure Monitor (Container Insights)
Logging:    Azure Log Analytics
Tracing:    Azure App Insights (if needed)
Dashboards: Azure Workbooks + Grafana
Alerting:   Azure Monitor Alerts
```

**Hybrid (Local + Cloud):**
```
Local:      Prometheus + Loki + Grafana (real-time)
Cloud:      Azure Log Analytics (long-term, compliance)
Bridge:     Azure Monitor Agent or custom forwarder
```

---

## CI/CD Tools

### Options Comparison

| Tool | Type | Best For | Self-Hosted |
|------|------|----------|-------------|
| **Azure DevOps** | Full platform | Azure ecosystem | Yes (Server) |
| **GitHub Actions** | Cloud-native | GitHub repos | Yes (runners) |
| **GitLab CI** | Full platform | GitLab repos | Yes |
| **Jenkins** | Self-hosted | Custom workflows | Yes |
| **ArgoCD** | GitOps | Kubernetes deployments | Yes |
| **Flux** | GitOps | Kubernetes deployments | Yes |
| **Tekton** | K8s-native | Cloud-native CI/CD | Yes |

### Recommendation by Scenario

| Scenario | CI | CD | Rationale |
|----------|----|----|-----------|
| Azure DevOps repos | Azure Pipelines | Flux | Native integration |
| GitHub repos | GitHub Actions | ArgoCD or Flux | Native integration |
| Multi-platform | Jenkins or GitLab | ArgoCD | Flexibility |
| K8s-native | Tekton | ArgoCD | All in-cluster |

### IPC Platform Choice: Azure DevOps + Flux

**Rationale:**
- Azure DevOps for source control and pipelines
- Flux for GitOps deployment to edge
- Arc integration for remote management
- Consistent with Azure-centric strategy

---

## Messaging & Data

### Options Comparison

| Platform | Type | Best For | Edge Suitability |
|----------|------|----------|------------------|
| **MQTT (Mosquitto)** | Pub/Sub | IoT devices | Excellent |
| **Azure IoT Hub** | Managed IoT | Azure integration | Good (cloud-dependent) |
| **Apache Kafka** | Streaming | High-throughput | Poor (heavy) |
| **NATS** | Messaging | Cloud-native | Excellent |
| **Redis Streams** | Streaming | Low-latency | Good |
| **Azure Event Hubs** | Managed streaming | Azure integration | Good (cloud-dependent) |

### Recommendation by Scenario

| Scenario | Recommended | Rationale |
|----------|-------------|-----------|
| IoT telemetry | MQTT → IoT Hub | Protocol translation at edge |
| Edge-to-edge | NATS or MQTT | Lightweight, fast |
| High-throughput analytics | Kafka (hub) + MQTT (edge) | Kafka at cloud/datacenter |
| Real-time processing | Redis Streams | Low latency, simple |

---

## Infrastructure as Code

### Options Comparison

| Tool | Best For | Learning Curve | Multi-Cloud |
|------|----------|----------------|-------------|
| **Terraform** | Infrastructure provisioning | Medium | Excellent |
| **Pulumi** | Developer-friendly IaC | Medium | Excellent |
| **ARM/Bicep** | Azure-native | Low (Azure) | Azure only |
| **CloudFormation** | AWS-native | Low (AWS) | AWS only |
| **Crossplane** | K8s-native IaC | High | Excellent |
| **Ansible** | Configuration management | Low | N/A |

### Recommendation

| Layer | Tool | Rationale |
|-------|------|-----------|
| Cloud infrastructure | Terraform | Multi-cloud, mature |
| Azure-specific | Bicep (alternative) | Native, simpler |
| Configuration | Ansible or PowerShell DSC | Idempotent config |
| Kubernetes | Kustomize + Flux | GitOps native |
| Secrets | External Secrets Operator | Multi-backend |

---

## Quick Reference: IPC Platform Stack

| Layer | Technology | Alternative |
|-------|------------|-------------|
| **OS** | Windows IoT Enterprise LTSC | Ubuntu Core |
| **Container Runtime** | containerd | Docker |
| **Orchestration** | AKS Edge Essentials (K3s) | MicroK8s |
| **GitOps** | Flux | ArgoCD |
| **Edge-Cloud** | Azure Arc | Rancher |
| **Messaging** | MQTT + Azure IoT Hub | NATS |
| **Metrics** | Azure Monitor + Prometheus | Datadog |
| **Logging** | Azure Log Analytics | Loki |
| **IaC** | Packer + Terraform | Pulumi |
| **CI/CD** | Azure DevOps Pipelines | GitHub Actions |
| **Secrets** | Workload Identity Federation | External Secrets |
