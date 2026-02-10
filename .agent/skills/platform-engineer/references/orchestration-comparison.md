# Orchestration Comparison

Comprehensive comparison of container and VM orchestration platforms for edge deployments. Covers Kubernetes distributions, Nomad, Docker Swarm, and VM-based orchestration.

## Platform Overview

### Container Orchestration

| Platform | Vendor | K8s Conformant | Best For |
|----------|--------|----------------|----------|
| **Kubernetes (full)** | CNCF | Yes | Large clusters, enterprise |
| **K3s** | Rancher/SUSE | Yes | Edge, IoT, resource-constrained |
| **K0s** | Mirantis | Yes | Minimal Kubernetes |
| **MicroK8s** | Canonical | Yes | Ubuntu edge, snap ecosystem |
| **AKS Edge Essentials** | Microsoft | Yes (K3s) | Windows + Azure |
| **EKS Anywhere** | Amazon | Yes | AWS ecosystem |
| **Anthos** | Google | Yes (GKE) | GCP ecosystem |
| **OpenShift** | Red Hat | Yes | Enterprise, regulated |
| **Nomad** | HashiCorp | No | Mixed workloads |
| **Docker Swarm** | Docker | No | Simple orchestration |

### VM Orchestration

| Platform | Type | Best For |
|----------|------|----------|
| **VMware vSphere** | Hypervisor | Enterprise virtualization |
| **Proxmox VE** | Hypervisor | Open-source virtualization |
| **Hyper-V** | Hypervisor | Windows environments |
| **KVM/libvirt** | Hypervisor | Linux native |
| **Nutanix** | HCI | Hyperconverged infrastructure |
| **Azure Stack HCI** | HCI | Azure hybrid |

---

## Kubernetes Distribution Comparison

### Resource Requirements

| Distribution | Min RAM | Min CPU | Min Disk | Nodes |
|--------------|---------|---------|----------|-------|
| Full K8s | 4GB | 2 cores | 20GB | 3+ |
| K3s | 512MB | 1 core | 1GB | 1+ |
| K0s | 512MB | 1 core | 1GB | 1+ |
| MicroK8s | 1GB | 1 core | 10GB | 1+ |
| AKS Edge | 2GB | 2 cores | 14GB | 1+ |
| EKS Anywhere | 2GB | 2 cores | 20GB | 1+ |

### Feature Comparison

| Feature | Full K8s | K3s | K0s | MicroK8s | AKS Edge |
|---------|----------|-----|-----|----------|----------|
| Single binary | ❌ | ✅ | ✅ | ❌ | ❌ |
| Built-in ingress | ❌ | ✅ Traefik | ❌ | ✅ | ✅ |
| Built-in LB | ❌ | ✅ ServiceLB | ❌ | ✅ MetalLB | ✅ |
| Embedded etcd | ❌ | ✅ SQLite/etcd | ✅ | ✅ dqlite | ✅ |
| Windows support | Limited | Limited | Limited | ❌ | ✅ |
| Air-gap install | ✅ | ✅ | ✅ | ✅ | ✅ |
| Auto-updates | ❌ | ❌ | ✅ | ✅ snap | ❌ |
| Arc integration | Manual | Manual | Manual | Manual | ✅ Native |
| HA support | ✅ | ✅ | ✅ | ✅ | Limited |

### K3s Deep Dive

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                     K3s Server Node                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   k3s binary                         │   │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐         │   │
│  │  │API Server │ │Controller │ │ Scheduler │         │   │
│  │  └───────────┘ │  Manager  │ └───────────┘         │   │
│  │                └───────────┘                        │   │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐         │   │
│  │  │  SQLite/  │ │  Traefik  │ │Local Path │         │   │
│  │  │   etcd    │ │  Ingress  │ │Provisioner│         │   │
│  │  └───────────┘ └───────────┘ └───────────┘         │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   containerd                         │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐               │   │
│  │  │  Pod 1  │ │  Pod 2  │ │  Pod N  │               │   │
│  │  └─────────┘ └─────────┘ └─────────┘               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Installation:**
```bash
# Single command install
curl -sfL https://get.k3s.io | sh -

# With options
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

# Air-gapped
# 1. Download binary and images
# 2. Place in /var/lib/rancher/k3s/agent/images/
# 3. Run k3s binary directly
```

**Best For:**
- Edge deployments with limited resources
- IoT gateways
- Development/testing environments
- Air-gapped installations

---

### AKS Edge Essentials Deep Dive

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                  Windows Host                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Hyper-V / WSL2                         │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │           Linux VM (CBL-Mariner)               │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │                K3s                       │  │  │   │
│  │  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐    │  │  │   │
│  │  │  │  │  Pod 1  │ │  Pod 2  │ │  Pod N  │    │  │  │   │
│  │  │  │  └─────────┘ └─────────┘ └─────────┘    │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
│                   Azure Arc Agent                           │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           ▼
                    Azure Arc (Cloud)
```

**Installation (PowerShell):**
```powershell
# Install AKS Edge module
Install-Module AksEdge -Repository PSGallery -Force

# Create single-node deployment
New-AksEdgeDeployment -NodeType Linux

# Or with configuration file
New-AksEdgeDeployment -JsonConfigFilePath .\aksedge-config.json
```

**Configuration (aksedge-config.json):**
```json
{
  "SchemaVersion": "1.9",
  "Version": "1.0",
  "DeploymentType": "SingleMachineCluster",
  "Init": {
    "ServiceIPRangeStart": "10.96.0.0",
    "ServiceIPRangeSize": 4096
  },
  "Network": {
    "ControlPlaneEndpointIp": "192.168.1.100",
    "NetworkPlugin": "calico"
  },
  "Machines": [
    {
      "LinuxNode": {
        "CpuCount": 4,
        "MemoryInMB": 4096,
        "DataSizeInGB": 20
      }
    }
  ]
}
```

**Best For:**
- Windows IoT Enterprise deployments
- Azure-centric organizations
- Industrial PC platforms
- Arc-enabled GitOps

---

## HashiCorp Nomad

### When to Choose Nomad over Kubernetes

| Scenario | Nomad | Kubernetes |
|----------|-------|------------|
| Mixed workloads (VMs + containers) | ✅ Better | ⚠️ KubeVirt |
| Simplicity is priority | ✅ Better | Complex |
| Small team/limited K8s expertise | ✅ Better | Learning curve |
| Legacy application migration | ✅ Better | Refactor needed |
| Pure container orchestration | ⚠️ Okay | ✅ Better |
| Cloud-native ecosystem | ⚠️ Limited | ✅ Rich |
| CNCF compliance requirement | ❌ No | ✅ Yes |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Nomad Cluster                            │
│                                                             │
│  ┌────────────────┐  ┌────────────────┐                    │
│  │  Server Node   │──│  Server Node   │  (Consensus)       │
│  └────────────────┘  └────────────────┘                    │
│           │                                                 │
│           ▼                                                 │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  │
│  │  Client Node   │  │  Client Node   │  │ Client Node  │  │
│  │ ┌────────────┐ │  │ ┌────────────┐ │  │┌────────────┐│  │
│  │ │ Container  │ │  │ │    VM      │ │  ││  Binary    ││  │
│  │ │   Task     │ │  │ │   Task     │ │  ││   Task     ││  │
│  │ └────────────┘ │  │ └────────────┘ │  │└────────────┘│  │
│  └────────────────┘  └────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Job Specification Example

```hcl
job "web-service" {
  datacenters = ["edge-site-1"]
  type        = "service"

  group "web" {
    count = 3

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "web-service"
      port = "http"
      
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "nginx:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
```

---

## VM Orchestration Options

### VMware vSphere

**Best For:**
- Enterprise environments
- Existing VMware investments
- VDI deployments
- Mission-critical workloads

**Edge Deployment:**
- vSphere on edge servers
- vSAN for distributed storage
- NSX for networking
- vCenter for management (can be remote)

### Hyper-V

**Best For:**
- Windows-centric environments
- Azure hybrid scenarios
- AKS Edge Essentials base
- Cost-sensitive deployments

**Edge Deployment:**
- Hyper-V Server (free) or Windows Server
- Storage Spaces Direct for HA storage
- System Center for management
- Azure Arc for hybrid management

### Proxmox VE

**Best For:**
- Open-source requirements
- Mixed VM + container (LXC)
- Budget-conscious deployments
- Small to medium clusters

**Edge Deployment:**
- Proxmox cluster across nodes
- Ceph for distributed storage
- Web-based management
- API for automation

---

## Mixed Workload Strategies

### Strategy 1: Kubernetes + VMs (KubeVirt)

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    KubeVirt                          │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │   │
│  │  │ VM (Legacy) │ │ VM (Windows)│ │   VM (DB)   │    │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  Container  │ │  Container  │ │  Container  │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

**Pros:** Single control plane, Kubernetes ecosystem
**Cons:** Complex, resource overhead, limited Windows support

### Strategy 2: Nomad (Native Mixed)

```
┌─────────────────────────────────────────────────────────────┐
│                      Nomad Cluster                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │ Container   │ │     VM      │ │   Binary    │           │
│  │ (Docker)    │ │ (QEMU/KVM)  │ │   (exec)    │           │
│  └─────────────┘ └─────────────┘ └─────────────┘           │
│        │                │                │                  │
│        └────────────────┼────────────────┘                  │
│                         │                                   │
│              Unified Scheduling & Networking                │
└─────────────────────────────────────────────────────────────┘
```

**Pros:** Simple, native VM support, low overhead
**Cons:** Smaller ecosystem, no K8s compatibility

### Strategy 3: Layered (Hypervisor + K8s)

```
┌─────────────────────────────────────────────────────────────┐
│                 Hypervisor (ESXi/Hyper-V)                   │
│  ┌────────────────────┐  ┌────────────────────┐            │
│  │    VM: Legacy App  │  │   VM: K8s Cluster  │            │
│  │    (Windows/Linux) │  │  ┌──────────────┐  │            │
│  │                    │  │  │  Containers  │  │            │
│  │                    │  │  └──────────────┘  │            │
│  └────────────────────┘  └────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

**Pros:** Clear separation, mature technologies
**Cons:** Multiple management planes, resource overhead

---

## Decision Framework

```
START: What workloads do you need to run?
  │
  ├─ Only containers (cloud-native apps)
  │   └─ Kubernetes (K3s for edge, AKS Edge for Windows)
  │
  ├─ Only VMs (legacy applications)
  │   └─ Hypervisor (Hyper-V, ESXi, Proxmox)
  │
  ├─ Mixed containers + VMs
  │   ├─ Kubernetes expertise available?
  │   │   └─ Yes → KubeVirt on Kubernetes
  │   │   └─ No → Nomad or Layered approach
  │   │
  │   └─ Simplicity priority?
  │       └─ Yes → Nomad
  │       └─ No → Layered (Hypervisor + K8s VMs)
  │
  └─ Unsure → Start with containers (K3s), add VM layer if needed
```

---

## IPC Platform Recommendation

**Selected:** AKS Edge Essentials (K3s-based)

**Rationale:**
1. Windows IoT Enterprise base requirement
2. Native Azure Arc integration
3. GitOps-ready with Flux
4. Single management plane (Azure)
5. Microsoft support for industrial scenarios
6. Path to AKS for larger deployments

**Trade-offs Accepted:**
- Higher resource footprint than pure K3s
- Azure dependency (acceptable for target market)
- Limited native Windows container support (Linux VMs used)
