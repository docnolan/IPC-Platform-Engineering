# IPC Platform Engineering
# Overview and Strategic Context

**Document Version:** 5.0  
**Last Updated:** January 27, 2026  
**Author:** Platform Engineering Team  
**Target Audience:** Engineering Leadership, Management  
**Classification:** Technical Reference  
**Build Timeline:** 30 Days

---

# Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Three Pillars](#2-the-three-pillars)
3. [Architecture Overview](#3-architecture-overview)
4. [Repository Structure](#4-repository-structure)
5. [Key Azure Resources](#5-key-azure-resources)

---

# 1. Executive Summary

## 1.1 What This PoC Demonstrates

This proof of concept demonstrates a **Platform Engineering approach to Industrial PC lifecycle management**. The solution transforms how IPCs are built, deployed, monitored, and maintained throughout their operational life inside control panels and test stands.



## 1.2 The Five Production Workloads

4. **Compliance Audit Log Forwarder** - CMMC/NIST-ready audit trail to Azure
5. **Edge Anomaly Detection** - Local ML inference for predictive maintenance

> **Note:** The PoC also includes five **simulators** that generate realistic industrial data for demonstration purposes. These simulators are placeholders for actual production equipment (PLCs, test systems, vision systems) and are not intended for customer deployment. See [Section 5.3](#53-component-descriptions) for details.





---

# 2. The Three Pillars

This PoC demonstrates three strategic capabilities that form the platform foundation:

## 2.1 Pillar 1: Automated Provisioning

**Problem:** Each IPC is manually configured, taking 4-8 hours with inconsistent results.

**Solution:** Packer-based golden images with security hardening baked in.

| Metric | Traditional | Platform Engineering |
|--------|-------------|---------------------|
| Provisioning time | 4-8 hours | <30 minutes |
| Configuration consistency | Variable | 100% identical |
| Security baseline | Manual checklist | Automated CIS Benchmark |
| Audit trail | None | Git-versioned, timestamped |

**Demo proof point:** Show the Packer template, explain CIS hardening, demonstrate pipeline trigger.

---

## 2.2 Pillar 2: Compliance as a Service

**Problem:** Defense and pharmaceutical customers require CMMC/NIST 800-171 compliance. Evidence gathering takes days per audit.

**Solution:** Continuous compliance monitoring with audit-ready reporting.

| Metric | Traditional | Platform Engineering |
|--------|-------------|---------------------|
| Audit log retention | Local (easily lost) | Azure (90-day, tamper-proof) |
| Evidence generation | Days of manual work | Single KQL query |
| Compliance visibility | Point-in-time snapshots | Real-time dashboards |
| Control coverage | Unknown | 72% of NIST 800-171 technical controls |

**Demo proof point:** Show the Azure Monitor Workbook with live security events and NIST control mapping.

---

## 2.3 Pillar 3: Zero-Touch Updates

**Problem:** Updating software on deployed panels requires truck rolls or risky remote desktop sessions.

**Solution:** GitOps-based deployment where code changes automatically flow to edge devices.

| Metric | Traditional | Platform Engineering |
|--------|-------------|---------------------|
| Update method | Truck roll / RDP | Git commit |
| Update time | Hours to days | <10 minutes |
| Rollback capability | Manual, error-prone | Git revert |
| Change tracking | Informal | Full audit trail |

**Demo proof point:** Live demo—create a PR, approve it, watch the pipeline build, see Flux deploy to the cluster.

---

# 3. Architecture Overview

## 3.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                  AZURE CLOUD                                    │
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                 │
│  │  Azure DevOps   │  │   Azure Arc     │  │  Azure Monitor  │                 │
│  │  • Git Repos    │  │  • Kubernetes   │  │  • Log Analytics│                 │
│  │  • CI/CD        │  │  • GitOps/Flux  │  │  • Workbooks    │                 │
│  │  • Work Items   │  │                 │  │                 │                 │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘                 │
│           │                    │                    │                           │
│  ┌────────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐                 │
│  │ Container       │  │  Azure IoT Hub  │  │  Azure Blob     │                 │
│  │ Registry (ACR)  │  │  (Telemetry)    │  │  Storage        │                 │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────┘                 │
│           │                    │                                                │
└───────────┼────────────────────┼────────────────────────────────────────────────┘
            │                    │
            │  Outbound HTTPS    │  Outbound MQTT/AMQP
            │  (No inbound!)     │  (No inbound!)
            ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           INDUSTRIAL PC (Edge)                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │  Windows 10 IoT Enterprise LTSC 2021 (Packer Golden Image)                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │ │
│  │  │  AKS Edge Essentials (K3s)                                          │  │ │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │  │ │
│  │  │  │ OPC-UA      │ │ Health      │ │ Log         │ │ Anomaly     │    │  │ │
│  │  │  │ Gateway     │ │ Monitor     │ │ Forwarder   │ │ Detection   │    │  │ │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘    │  │ │
│  │  │  ┌─────────────┐                                                    │  │ │
│  │  │  │ Test Data   │  Azure Arc Agent                                   │  │ │
│  │  │  │ Collector   │  (Cloud Connectivity)                              │  │ │
│  │  │  └─────────────┘                                                    │  │ │
│  │  └─────────────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Key Architectural Decisions

1. **All connections are outbound** - No firewall rules required at customer sites
2. **Workload Identity Federation** - Zero stored secrets in the platform
3. **GitOps deployment** - Git is the source of truth for all configuration
4. **Containerized workloads** - Traditional apps (HMI, OPC servers) run natively; value-add services run in K8s

## 3.3 Component Descriptions

### Azure Components

| Component | Purpose | Why It's Needed |
|-----------|---------|-----------------|
| **Azure DevOps** | CI/CD pipelines, Git repos, artifact storage | Automates image builds, stores infrastructure-as-code |
| **Azure Arc** | Hybrid management plane | Single pane of glass for all IPCs regardless of location |
| **Azure Container Registry** | Container image storage | Secure, private registry for edge workload images |
| **Azure Monitor / Log Analytics** | Centralized logging and dashboards | Visibility across all deployed panels |
| **Azure IoT Hub** | Telemetry ingestion | Receives data from OPC-UA gateway and data collectors |

### IPC Components

| Component | Purpose | Why It's Needed |
|-----------|---------|-----------------|
| **Windows 10 IoT Enterprise LTSC** | Base operating system | 10-year support, minimal bloat, enterprise features |
| **CIS Benchmark Hardening** | Security baseline | CMMC/NIST compliance foundation |
| **Traditional Applications** | HMI, OPC servers, test apps | Customer's core automation (not containerized) |
| **AKS Edge Essentials** | Lightweight Kubernetes | Runs containerized value-add services |
| **Azure Arc Agent** | Cloud connectivity | Enables remote management without VPN |

### Containerized Workloads

The PoC includes two categories of containerized workloads:

#### Production Workloads (Ship to Customers)

These are the **core services** designed for customer deployment:

| Workload | Purpose | Data Flow |
|----------|---------|-----------|
| **OPC-UA Gateway** | Protocol translation | OPC-UA → MQTT → Azure IoT Hub |
| **Test Data Collector** | Results upload | File/DB → Azure Blob/IoT Hub |
| **Health Monitor** | System telemetry | Windows perf counters → Azure Monitor |
| **Log Forwarder** | Audit compliance | Windows Event Logs → Log Analytics |
| **Anomaly Detection** | Edge ML inference | Sensor data → Local model → Alerts |

#### PoC Simulators (Demo Only — Not for Production)

These workloads **generate realistic industrial data** to demonstrate platform capabilities. In production, they would be replaced by actual equipment (PLCs, test systems, vision cameras):

| Simulator | Simulates | Data Pattern | Business Line |
|-----------|-----------|--------------|-------------------|
| **OPC-UA Simulator** | Generic PLC | Time-series tags | General automation |
| **EV Battery Simulator** | Battery pack tester (96 cells) | High-speed, high-cardinality | Battery Test Systems |
| **Vision Simulator** | Machine vision inspection | Event-based (PASS/FAIL) | Machine Vision Systems |
| **Motion Simulator** | 3-axis servo gantry (OPC-UA) | Real-time state | Robotics & Motion Control |
| **Motion Gateway** | Motion OPC-UA to IoT Hub bridge | Time-series | (Supports Motion Simulator) |

> **Why multiple simulators?** Our customers generate diverse data patterns. Battery testers produce thousands of metrics per second. Vision systems produce discrete events. Motion systems require correlated real-time state. The simulators prove the platform handles **all** of these patterns—not just generic OPC-UA.

## 3.4 Network Architecture

**Critical Design Principle: All connections are OUTBOUND from the IPC.**

No inbound firewall rules are required at customer sites. The Arc agent and IoT Hub clients initiate outbound HTTPS connections to Azure endpoints.

```
IPC (Inside Customer Firewall)
    │
    ├──► Azure Arc Endpoints (HTTPS 443)
    │    ├── *.guestconfiguration.azure.com
    │    ├── *.his.arc.azure.com
    │    ├── *.dp.kubernetesconfiguration.azure.com
    │    └── management.azure.com
    │
    ├──► Azure IoT Hub (MQTT 8883 or AMQP 5671)
    │    └── {iothub-name}.azure-devices.net
    │
    ├──► Azure Container Registry (HTTPS 443)
    │    └── {acr-name}.azurecr.io
    │
    └──► Azure Monitor (HTTPS 443)
         └── *.ods.opinsights.azure.com
```

## 3.5 Security Architecture

| Layer | Control | NIST 800-171 Mapping |
|-------|---------|---------------------|
| Identity | Workload Identity Federation (no secrets) | 3.5.1, 3.5.2 |
| Network | Outbound-only, TLS 1.2+ | 3.13.8, 3.13.15 |
| Host | CIS Benchmark Level 1 hardening | 3.4.1, 3.4.2, 3.4.6 |
| Authentication | NTLMv2 only, 14-char passwords | 3.5.7, 3.5.8 |
| Audit | Comprehensive event logging | 3.3.1, 3.3.2 |
| Encryption | BitLocker (recommended), TLS in transit | 3.13.8, 3.13.16 |

---



---

# 4. Repository Structure

All implementation code lives in the Azure DevOps repository, cloned locally to:

```
C:\Projects\IPC-Platform-Engineering\
├── docker/                         # Dockerfiles and Python source
│   ├── opcua-gateway/              # [Production] OPC-UA to IoT Hub
│   ├── health-monitor/             # [Production] System health metrics
│   ├── log-forwarder/              # [Production] Security event logs
│   ├── anomaly-detection/          # [Production] Edge ML alerting
│   ├── test-data-collector/        # [Production] Test results upload
│   ├── opcua-simulator/            # [Simulator] Generic PLC
│   ├── ev-battery-simulator/       # [Simulator] 96-cell battery pack
│   ├── vision-simulator/           # [Simulator] Quality inspection
│   ├── motion-simulator/           # [Simulator] 3-axis gantry OPC-UA
│   └── motion-gateway/             # [Simulator] Motion OPC-UA bridge
├── kubernetes/                     # K8s manifests (GitOps source)
│   └── workloads/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       └── [workload folders]/
├── packer/                         # Golden image definition
│   └── windows-iot-enterprise/
├── pipelines/                      # Azure DevOps pipeline YAML
├── compliance/                     # CIS scripts, NIST mapping
└── docs/                           # This guide and supporting docs
```

---

# 5. Key Azure Resources

| Resource | Name | Resource Group |
|----------|------|----------------|
| Subscription | Azure subscription 1 | — |
| Container Registry | `<your-acr-name>` | rg-ipc-platform-acr |
| IoT Hub | `<your-iothub-name>` | rg-ipc-platform-monitoring |
| Log Analytics | `<your-workspace-name>` | rg-ipc-platform-monitoring |
| Blob Storage | `stipcplatformXXXX` | rg-ipc-platform-monitoring |
| Arc Cluster | `aks-edge-ipc-factory-01` | rg-ipc-platform-arc |

**Full resource details in [01-Azure-Foundation.md](01-Azure-Foundation.md).**

---

*End of Overview Section*

**Next:** [01-Azure-Foundation.md](01-Azure-Foundation.md)
