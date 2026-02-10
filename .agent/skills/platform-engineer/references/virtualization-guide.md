# Virtualization Guide

Comprehensive guide for virtualization technologies in edge environments. Covers hypervisors, hyperconverged infrastructure (HCI), and integration with container orchestration.

## Virtualization Options

### Hypervisor Comparison

| Hypervisor | Type | License | Best For | Windows Support |
|------------|------|---------|----------|-----------------|
| **VMware ESXi** | Type 1 | Commercial | Enterprise, mission-critical | Excellent |
| **Hyper-V** | Type 1 | Windows license | Windows environments | Native |
| **KVM/QEMU** | Type 1 | Open source | Linux environments | Good |
| **Proxmox VE** | Type 1 | Open source | Small-medium clusters | Good |
| **VirtualBox** | Type 2 | Free/Commercial | Development | Good |

### Feature Comparison

| Feature | ESXi | Hyper-V | KVM | Proxmox |
|---------|------|---------|-----|---------|
| Live migration | ✅ vMotion | ✅ Live Migration | ✅ | ✅ |
| HA clustering | ✅ vSphere HA | ✅ Failover Cluster | ✅ | ✅ |
| Storage integration | ✅ vSAN | ✅ Storage Spaces | ✅ Ceph | ✅ Ceph/ZFS |
| GPU passthrough | ✅ | ✅ | ✅ | ✅ |
| Nested virtualization | ✅ | ✅ | ✅ | ✅ |
| REST API | ✅ | ✅ PowerShell | ✅ libvirt | ✅ |
| Web management | ✅ vSphere | ❌ (WAC) | ❌ | ✅ |
| Cost | $$$ | Included | Free | Free |

---

## VMware vSphere

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    vCenter Server                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  • Centralized management                            │   │
│  │  • vMotion coordination                              │   │
│  │  • DRS (Distributed Resource Scheduler)              │   │
│  │  • HA (High Availability)                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                  │
│       ┌──────────────────┼──────────────────┐              │
│       │                  │                  │              │
│       ▼                  ▼                  ▼              │
│  ┌─────────┐        ┌─────────┐        ┌─────────┐        │
│  │ ESXi    │        │ ESXi    │        │ ESXi    │        │
│  │ Host 1  │        │ Host 2  │        │ Host 3  │        │
│  │┌───┐┌───┐│       │┌───┐┌───┐│       │┌───┐┌───┐│       │
│  ││VM ││VM ││       ││VM ││VM ││       ││VM ││VM ││       │
│  │└───┘└───┘│       │└───┘└───┘│       │└───┘└───┘│       │
│  └─────────┘        └─────────┘        └─────────┘        │
│       │                  │                  │              │
│       └──────────────────┼──────────────────┘              │
│                          │                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  vSAN / Shared Storage                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Edge Deployment Options

| Option | Description | Use Case |
|--------|-------------|----------|
| **vSphere Standalone** | Single ESXi host | Small edge sites |
| **vSphere Cluster** | Multiple hosts + vCenter | Larger edge with HA |
| **vSAN 2-Node** | Minimum HA configuration | Remote offices |
| **vSphere+ (Cloud)** | Cloud-managed vSphere | Distributed edge fleet |

### Automation (PowerCLI)

```powershell
# Connect to vCenter
Connect-VIServer -Server vcenter.example.com -Credential $cred

# Create new VM
New-VM -Name "edge-ipc-01" `
  -ResourcePool "Edge-Cluster" `
  -Datastore "vsan-datastore" `
  -NumCpu 4 `
  -MemoryGB 8 `
  -DiskGB 100 `
  -NetworkName "VM-Network" `
  -GuestId "windows2019srv_64Guest"

# Clone from template
New-VM -Name "edge-ipc-02" `
  -Template "Windows-IoT-Template" `
  -ResourcePool "Edge-Cluster" `
  -Datastore "vsan-datastore"

# Power operations
Start-VM -VM "edge-ipc-01"
Restart-VMGuest -VM "edge-ipc-01"  # Graceful
```

---

## Microsoft Hyper-V

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Windows Server Host                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Hyper-V Role                         │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │              Hypervisor (Type 1)                │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │   │
│  │  │  VM 1   │  │  VM 2   │  │  VM 3   │  │ Parent  │ │   │
│  │  │(Guest)  │  │(Guest)  │  │(Guest)  │  │Partition│ │   │
│  │  └─────────┘  └─────────┘  └─────────┘  │(Mgmt OS)│ │   │
│  │                                          └─────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │    Virtual Switch (External/Internal/Private)        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Options

| Option | OS | Use Case |
|--------|-----|----------|
| **Windows Server** | Full GUI or Core | Production |
| **Hyper-V Server** | Free, headless | Cost-sensitive |
| **Windows 10/11 Pro** | Client Hyper-V | Development |
| **Azure Stack HCI** | Azure-integrated | Hybrid cloud |

### PowerShell Management

```powershell
# Create virtual switch
New-VMSwitch -Name "External-Switch" `
  -NetAdapterName "Ethernet" `
  -AllowManagementOS $true

# Create VM
New-VM -Name "edge-ipc-01" `
  -Generation 2 `
  -MemoryStartupBytes 4GB `
  -NewVHDPath "C:\VMs\edge-ipc-01.vhdx" `
  -NewVHDSizeBytes 100GB `
  -SwitchName "External-Switch"

# Configure VM
Set-VM -Name "edge-ipc-01" `
  -ProcessorCount 4 `
  -DynamicMemory `
  -MemoryMinimumBytes 2GB `
  -MemoryMaximumBytes 8GB

# Enable nested virtualization (for AKS Edge)
Set-VMProcessor -VMName "edge-ipc-01" `
  -ExposeVirtualizationExtensions $true

# Attach ISO
Add-VMDvdDrive -VMName "edge-ipc-01" `
  -Path "C:\ISOs\windows-iot.iso"

# Start VM
Start-VM -Name "edge-ipc-01"
```

### Failover Clustering

```powershell
# Create cluster (requires shared storage or S2D)
New-Cluster -Name "Edge-Cluster" `
  -Node @("node1", "node2") `
  -StaticAddress "10.0.0.100"

# Add VM to cluster
Add-ClusterVirtualMachineRole `
  -VMName "edge-ipc-01" `
  -Cluster "Edge-Cluster"

# Configure HA
Set-ClusterOwnerNode -Resource "edge-ipc-01" `
  -Owners @("node1", "node2")
```

---

## KVM/libvirt (Linux)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Linux Host                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    QEMU/KVM                          │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │           KVM Kernel Module                     │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌─────────────────────────────────────────────────┐ │   │
│  │  │                 libvirt                         │ │   │
│  │  │  • virsh CLI                                    │ │   │
│  │  │  • virt-manager GUI                             │ │   │
│  │  │  • API for automation                           │ │   │
│  │  └─────────────────────────────────────────────────┘ │   │
│  │                                                      │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │  VM 1   │  │  VM 2   │  │  VM 3   │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### virsh Management

```bash
# List VMs
virsh list --all

# Create VM from XML
virsh define /path/to/vm.xml

# Start/Stop
virsh start edge-ipc-01
virsh shutdown edge-ipc-01
virsh destroy edge-ipc-01  # Force stop

# Clone VM
virt-clone --original template-vm \
  --name edge-ipc-01 \
  --file /var/lib/libvirt/images/edge-ipc-01.qcow2

# Snapshot
virsh snapshot-create-as edge-ipc-01 \
  --name "pre-upgrade" \
  --description "Before K8s upgrade"

# Revert snapshot
virsh snapshot-revert edge-ipc-01 --snapshotname "pre-upgrade"
```

### VM Definition (XML)

```xml
<domain type='kvm'>
  <name>edge-ipc-01</name>
  <memory unit='GiB'>8</memory>
  <vcpu>4</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/var/lib/libvirt/images/edge-ipc-01.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='bridge'>
      <source bridge='br0'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>
```

---

## Hyperconverged Infrastructure (HCI)

### HCI Comparison

| Solution | Hypervisor | Storage | Management | Best For |
|----------|------------|---------|------------|----------|
| **VMware vSAN** | ESXi | vSAN | vCenter | VMware shops |
| **Azure Stack HCI** | Hyper-V | S2D | Windows Admin Center | Azure hybrid |
| **Nutanix** | AHV/ESXi/Hyper-V | Nutanix | Prism | Multi-hypervisor |
| **Proxmox VE** | KVM | Ceph/ZFS | Web UI | Open source |
| **Scale Computing** | KVM | SCRIBE | SC//Platform | Edge-focused |

### Azure Stack HCI

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                   Azure Stack HCI Cluster                   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Node 1    │  │   Node 2    │  │   Node 3    │         │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │         │
│  │ │ Hyper-V │ │  │ │ Hyper-V │ │  │ │ Hyper-V │ │         │
│  │ │   VMs   │ │  │ │   VMs   │ │  │ │   VMs   │ │         │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │         │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │         │
│  │ │ Storage │ │  │ │ Storage │ │  │ │ Storage │ │         │
│  │ │ Spaces  │ │  │ │ Spaces  │ │  │ │ Spaces  │ │         │
│  │ │ Direct  │ │  │ │ Direct  │ │  │ │ Direct  │ │         │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          │                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Storage Spaces Direct (S2D) Pool           │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                    Azure Arc
                           │
                           ▼
                    ┌──────────────┐
                    │    Azure     │
                    └──────────────┘
```

**Benefits for Edge:**
- Azure Arc integration
- Azure Kubernetes Service (AKS) hybrid
- Windows Admin Center management
- Azure Backup integration
- Consumption-based billing option

---

## VM + Container Integration

### Pattern: K8s on VMs

```
┌─────────────────────────────────────────────────────────────┐
│                    Hypervisor                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Kubernetes Cluster VMs                 │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │ Control     │  │   Worker    │  │   Worker    │ │    │
│  │  │ Plane VM    │  │    VM 1     │  │    VM 2     │ │    │
│  │  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │ │    │
│  │  │ │ K8s     │ │  │ │Containers│ │  │ │Containers│ │ │    │
│  │  │ │ Master  │ │  │ └─────────┘ │  │ └─────────┘ │ │    │
│  │  │ └─────────┘ │  └─────────────┘  └─────────────┘ │    │
│  │  └─────────────┘                                   │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Legacy Application VMs                 │    │
│  │  ┌─────────────┐  ┌─────────────┐                  │    │
│  │  │ Windows     │  │  Database   │                  │    │
│  │  │ Server App  │  │   Server    │                  │    │
│  │  └─────────────┘  └─────────────┘                  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Best Practices

1. **Dedicated resources** for K8s VMs
2. **Pin K8s VMs** to avoid migration during critical operations
3. **Separate storage** for K8s persistent volumes
4. **Network isolation** between K8s and legacy VMs
5. **Backup both** VM snapshots and K8s-level backups

---

## Edge Hardware Considerations

### Minimum Specifications (Single-Node)

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB | 16+ GB |
| Storage | 128 GB SSD | 256+ GB NVMe |
| Network | 1 GbE | 10 GbE |

### Nested Virtualization Requirements

For AKS Edge Essentials on Hyper-V:

```powershell
# Enable nested virtualization
Set-VMProcessor -VMName "AKS-Edge-Host" `
  -ExposeVirtualizationExtensions $true

# Required VM settings
Set-VM -VMName "AKS-Edge-Host" `
  -MemoryStartupBytes 8GB `
  -ProcessorCount 4

# Enable MAC address spoofing (for container networking)
Set-VMNetworkAdapter -VMName "AKS-Edge-Host" `
  -MacAddressSpoofing On
```
