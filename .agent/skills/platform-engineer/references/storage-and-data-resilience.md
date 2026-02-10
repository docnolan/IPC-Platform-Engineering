# Storage and Data Resilience

Comprehensive guide for software-defined storage, backup strategies, disaster recovery, and data replication in edge environments.

## Storage Architecture for Edge

### Storage Tiers

| Tier | Performance | Capacity | Use Case | Technology |
|------|-------------|----------|----------|------------|
| **Hot** | High IOPS | Small | Real-time data, databases | NVMe SSD |
| **Warm** | Medium | Medium | Application data, logs | SATA SSD |
| **Cold** | Low | Large | Archives, backups | HDD, Cloud |
| **Archive** | Very Low | Very Large | Long-term retention | Cloud Blob/Glacier |

### Edge Storage Challenges

| Challenge | Impact | Mitigation |
|-----------|--------|------------|
| Limited capacity | Can't store everything locally | Tiering, cloud offload |
| No SAN/NAS | No shared storage | Software-defined storage |
| Network unreliability | Can't depend on cloud storage | Local-first architecture |
| Physical access | Security risk | Encryption at rest |
| Single node common | No built-in redundancy | Off-site replication |

---

## Software-Defined Storage Options

### Comparison Matrix

| Solution | Type | Min Nodes | K8s Native | Complexity | Best For |
|----------|------|-----------|------------|------------|----------|
| **Local PV** | Local | 1 | ✅ | Very Low | Single node |
| **Longhorn** | Distributed | 1+ | ✅ | Low | Small edge clusters |
| **OpenEBS** | Distributed | 1+ | ✅ | Medium | Flexible engines |
| **Rook-Ceph** | Distributed | 3+ | ✅ | High | Large clusters |
| **Robin.io** | Distributed | 3+ | ✅ | Medium | Stateful apps |
| **Portworx** | Distributed | 3+ | ✅ | Medium | Enterprise |
| **Azure Blob CSI** | Cloud | N/A | ✅ | Low | Cloud-connected |

---

### Longhorn (Recommended for Edge)

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Node 1    │  │   Node 2    │  │   Node 3    │         │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │         │
│  │ │Longhorn │ │  │ │Longhorn │ │  │ │Longhorn │ │         │
│  │ │ Engine  │ │  │ │ Replica │ │  │ │ Replica │ │         │
│  │ └────┬────┘ │  │ └────┬────┘ │  │ └────┬────┘ │         │
│  │      │      │  │      │      │  │      │      │         │
│  │ ┌────▼────┐ │  │ ┌────▼────┐ │  │ ┌────▼────┐ │         │
│  │ │Local SSD│ │  │ │Local SSD│ │  │ │Local SSD│ │         │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Longhorn Manager                        │   │
│  │  • Volume scheduling                                 │   │
│  │  • Replica placement                                 │   │
│  │  • Backup orchestration                              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Installation:**
```bash
# Helm installation
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=2
```

**StorageClass:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-edge
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fromBackup: ""
```

**Best Practices:**
- Replica count = min(3, number of nodes)
- Use dedicated disks for Longhorn
- Enable backups to S3-compatible storage
- Monitor disk space alerts

---

### Ceph (via Rook)

**Best For:** Large edge clusters (3+ nodes), high performance requirements

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      Rook Operator                          │
│                           │                                 │
│  ┌────────────────────────┼────────────────────────────┐   │
│  │                   Ceph Cluster                       │   │
│  │                                                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │   MON    │  │   MON    │  │   MON    │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  │                                                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │   OSD    │  │   OSD    │  │   OSD    │          │   │
│  │  │ (Node 1) │  │ (Node 2) │  │ (Node 3) │          │   │
│  │  └──────────┘  └──────────┘  └──────────┘          │   │
│  │                                                      │   │
│  │  ┌────────────────────────────────────────────────┐ │   │
│  │  │    MDS (CephFS)    │    RGW (Object)          │ │   │
│  │  └────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**When to Use Ceph:**
- 3+ nodes available
- Need block, file, AND object storage
- High IOPS requirements
- Team has Ceph expertise

---

## Backup Strategies

### 3-2-1 Rule for Edge

```
┌─────────────────────────────────────────────────────────────┐
│                    3-2-1 BACKUP RULE                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   3 Copies of Data                                         │
│   ├── 1. Production data (Edge)                            │
│   ├── 2. Local backup (Edge - different disk)              │
│   └── 3. Remote backup (Cloud or Hub)                      │
│                                                             │
│   2 Different Storage Types                                 │
│   ├── 1. SSD/NVMe (Production)                             │
│   └── 2. Object storage (Backup)                           │
│                                                             │
│   1 Offsite Copy                                           │
│   └── Cloud (Azure Blob, S3) or Regional Hub              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Backup Components

| Component | What to Backup | Frequency | Retention |
|-----------|----------------|-----------|-----------|
| Kubernetes state | etcd snapshot | Hourly | 7 days |
| Application data | PVC contents | Daily | 30 days |
| Configuration | Git repo | On change | Indefinite |
| Compliance logs | Log Analytics | Continuous | 90+ days |
| Golden images | Image registry | On build | 3 versions |

### Kubernetes Backup with Velero

**Installation:**
```bash
# Install Velero with Azure provider
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.7.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config resourceGroup=rg-backups,storageAccount=stbackups \
  --snapshot-location-config resourceGroup=rg-backups,subscriptionId=$SUBSCRIPTION_ID
```

**Backup Schedule:**
```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  template:
    includedNamespaces:
      - dmc-workloads
    storageLocation: default
    volumeSnapshotLocations:
      - default
    ttl: 720h  # 30 days
```

---

## Disaster Recovery

### RPO and RTO Targets

| Tier | RPO (Data Loss) | RTO (Downtime) | Strategy |
|------|-----------------|----------------|----------|
| **Critical** | < 1 minute | < 15 minutes | Sync replication, hot standby |
| **Important** | < 1 hour | < 1 hour | Async replication, warm standby |
| **Standard** | < 24 hours | < 4 hours | Daily backups, cold standby |
| **Archive** | < 7 days | < 24 hours | Weekly backups |

### DR Architecture Patterns

#### Pattern 1: Active-Passive (Hot Standby)

```
┌─────────────────┐         ┌─────────────────┐
│  Primary Site   │ ──────▶ │  Standby Site   │
│   (Active)      │  Sync   │   (Passive)     │
│                 │  Repl   │                 │
│  Production     │         │  Ready to       │
│  Traffic        │         │  Take Over      │
└─────────────────┘         └─────────────────┘
        │                           │
        └───────── Failover ────────┘
                   (Manual/Auto)
```

**Characteristics:**
- Near-zero RPO
- Fast RTO (minutes)
- High cost (2x infrastructure)
- Best for critical workloads

#### Pattern 2: Active-Passive (Warm Standby)

```
┌─────────────────┐         ┌─────────────────┐
│  Primary Site   │ ──────▶ │  Standby Site   │
│   (Active)      │  Async  │   (Passive)     │
│                 │  Repl   │                 │
│  Production     │         │  Minimal        │
│  Traffic        │         │  Resources      │
└─────────────────┘         └─────────────────┘
```

**Characteristics:**
- RPO = replication lag (minutes to hours)
- RTO = startup time + data sync
- Medium cost
- Good balance for most workloads

#### Pattern 3: Backup and Restore (Cold)

```
┌─────────────────┐         ┌─────────────────┐
│  Primary Site   │ ──────▶ │  Cloud Backup   │
│                 │ Backup  │   (Azure Blob)  │
│                 │         │                 │
└─────────────────┘         └────────┬────────┘
                                     │
                            On Disaster:
                                     │
                                     ▼
                            ┌─────────────────┐
                            │  Recovery Site  │
                            │  (Spin up)      │
                            └─────────────────┘
```

**Characteristics:**
- RPO = backup frequency
- RTO = restore time + validation
- Lowest cost
- Acceptable for non-critical

### Edge-Specific DR Considerations

| Challenge | Solution |
|-----------|----------|
| Single-node common | Off-site replication to cloud |
| Limited bandwidth | Incremental/delta replication |
| Compliance requirements | Encrypted backups, audit trail |
| No on-site IT | Automated recovery procedures |
| Hardware failure | Rapid replacement + restore |

---

## Data Replication Strategies

### Synchronous Replication

```
Write Request
     │
     ▼
┌─────────────────┐
│  Primary Node   │
│  1. Write data  │
│  2. Wait for    │──── Sync ────▶  ┌─────────────────┐
│     replica ACK │                 │  Replica Node   │
│  3. Return OK   │ ◀─── ACK ─────  │  Write data     │
└─────────────────┘                 └─────────────────┘
```

**Characteristics:**
- Zero data loss (RPO = 0)
- Higher latency
- Requires fast, reliable network
- Used for: Financial data, compliance logs

### Asynchronous Replication

```
Write Request
     │
     ▼
┌─────────────────┐                 ┌─────────────────┐
│  Primary Node   │                 │  Replica Node   │
│  1. Write data  │                 │                 │
│  2. Return OK   │                 │                 │
│  3. Queue repl  │──── Async ────▶ │  Apply writes   │
└─────────────────┘    (Later)      └─────────────────┘
```

**Characteristics:**
- Possible data loss (RPO = lag)
- Lower latency for writes
- Tolerates unreliable network
- Used for: Telemetry, logs, backups

### Edge-to-Cloud Replication Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                        EDGE SITE                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Local Storage                       │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │   │
│  │  │ Hot Data │  │ Log Data │  │  Backups │          │   │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘          │   │
│  │       │             │             │                 │   │
│  └───────┼─────────────┼─────────────┼─────────────────┘   │
│          │             │             │                     │
│          ▼             ▼             ▼                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Replication Agent                       │   │
│  │  • Compress • Encrypt • Queue • Retry               │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           │ HTTPS (Outbound)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                         AZURE                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  IoT Hub     │  │Log Analytics │  │ Blob Storage │      │
│  │  (Telemetry) │  │   (Logs)     │  │  (Backups)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

---

## IPC Platform Storage Configuration

### Recommended Setup (Single-Node)

```yaml
# Storage configuration for single-node edge
Storage:
  OS Disk: 
    Type: NVMe SSD
    Size: 128GB
    Contents: Windows, K8s, Workloads
    
  Data Disk:
    Type: SATA SSD
    Size: 256GB+
    Contents: Persistent volumes, local backups
    
  Backup Target:
    Type: Azure Blob Storage
    Container: ipc-backups
    Retention: 30 days
```

### Backup Schedule

| Data Type | Method | Frequency | Target |
|-----------|--------|-----------|--------|
| K8s state | etcd snapshot | Every 6 hours | Azure Blob |
| Workload PVCs | Velero backup | Daily | Azure Blob |
| Compliance logs | Streaming | Continuous | Log Analytics |
| Configuration | Git push | On change | Azure DevOps |

### Recovery Procedure

```
DISASTER RECOVERY PROCEDURE
===========================

1. Hardware Replacement
   └── Deploy new IPC with golden image

2. Platform Bootstrap
   └── Connect to Azure Arc
   └── GitOps applies configuration

3. Data Restore
   └── Velero restore from latest backup
   └── Verify data integrity

4. Validation
   └── Health checks pass
   └── Data flow verified
   └── Monitoring active

Estimated RTO: 2-4 hours (hardware dependent)
```
