# Language Selection Guide

Decision framework for selecting programming languages in edge platform engineering. Covers Go, Python, Rust, and PowerShell with use cases, trade-offs, and best practices.

## Language Comparison Matrix

| Factor | Go | Python | Rust | PowerShell |
|--------|-----|--------|------|------------|
| **Performance** | High | Low-Medium | Very High | Medium |
| **Memory Safety** | GC-managed | GC-managed | Compile-time | GC-managed |
| **Binary Size** | Small-Medium | N/A (interpreted) | Small | N/A |
| **Startup Time** | Fast | Slow | Fast | Medium |
| **Learning Curve** | Medium | Low | High | Low |
| **Concurrency** | Excellent | Good (asyncio) | Excellent | Limited |
| **Cloud-Native Ecosystem** | Excellent | Good | Growing | Azure-focused |
| **Windows Integration** | Good | Good | Good | Excellent |
| **Cross-Platform** | Excellent | Excellent | Excellent | Good (Core) |

---

## Go

### When to Use

| Use Case | Suitability | Rationale |
|----------|-------------|-----------|
| CLI tools | ✅ Excellent | Single binary, fast startup |
| Kubernetes operators | ✅ Excellent | Native ecosystem (client-go) |
| API services | ✅ Excellent | Performance, concurrency |
| Cloud-native tools | ✅ Excellent | Industry standard |
| System utilities | ✅ Good | Cross-platform, compiled |
| Data processing | ⚠️ Okay | Less ecosystem than Python |
| Quick scripts | ❌ Poor | Verbose for simple tasks |

### Characteristics

**Strengths:**
- Compiles to single static binary
- Built-in concurrency (goroutines, channels)
- Strong standard library
- Fast compilation
- Kubernetes ecosystem native language

**Weaknesses:**
- Verbose error handling
- No generics until Go 1.18+
- Limited metaprogramming
- Smaller ML/data science ecosystem

### Code Pattern: Kubernetes Client

```go
package main

import (
    "context"
    "fmt"
    "log"

    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

func main() {
    // Load kubeconfig
    config, err := clientcmd.BuildConfigFromFlags("", 
        clientcmd.RecommendedHomeFile)
    if err != nil {
        log.Fatal(err)
    }

    // Create client
    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        log.Fatal(err)
    }

    // List pods
    pods, err := clientset.CoreV1().Pods("default").List(
        context.TODO(), metav1.ListOptions{})
    if err != nil {
        log.Fatal(err)
    }

    for _, pod := range pods.Items {
        fmt.Printf("Pod: %s, Status: %s\n", 
            pod.Name, pod.Status.Phase)
    }
}
```

### Best Practices

- Use `context` for cancellation and timeouts
- Handle errors explicitly (no exceptions)
- Use `defer` for cleanup
- Prefer composition over inheritance
- Use interfaces for abstraction
- Run `go fmt` and `go vet` before commit

---

## Python

### When to Use

| Use Case | Suitability | Rationale |
|----------|-------------|-----------|
| Data processing | ✅ Excellent | pandas, numpy ecosystem |
| ML/AI workloads | ✅ Excellent | TensorFlow, PyTorch |
| Automation scripts | ✅ Excellent | Quick development |
| API services | ✅ Good | FastAPI, Flask |
| CLI tools | ✅ Good | Click, argparse |
| OT/Industrial | ✅ Good | OPC-UA libraries |
| Performance-critical | ❌ Poor | Interpreted, GIL |
| Edge deployment (resource) | ⚠️ Okay | Runtime overhead |

### Characteristics

**Strengths:**
- Rapid development
- Extensive ecosystem (PyPI)
- Excellent for data science
- Easy to learn
- OPC-UA and industrial libraries

**Weaknesses:**
- Slower execution than compiled languages
- Runtime dependency management
- GIL limits true parallelism
- Larger deployment footprint

### Code Pattern: OPC-UA Client

```python
#!/usr/bin/env python3
"""OPC-UA client for industrial data collection."""

import asyncio
import logging
from typing import List, Any

from asyncua import Client, ua

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class OPCUACollector:
    """Collects data from OPC-UA server."""
    
    def __init__(self, endpoint: str) -> None:
        self.endpoint = endpoint
        self.client = Client(endpoint)
    
    async def connect(self) -> None:
        """Establish connection to OPC-UA server."""
        await self.client.connect()
        logger.info(f"Connected to {self.endpoint}")
    
    async def read_values(self, node_ids: List[str]) -> dict[str, Any]:
        """Read values from multiple nodes."""
        results = {}
        for node_id in node_ids:
            try:
                node = self.client.get_node(node_id)
                value = await node.read_value()
                results[node_id] = value
            except ua.UaError as e:
                logger.error(f"Failed to read {node_id}: {e}")
                results[node_id] = None
        return results
    
    async def disconnect(self) -> None:
        """Close connection."""
        await self.client.disconnect()


async def main():
    collector = OPCUACollector("opc.tcp://localhost:4840")
    
    try:
        await collector.connect()
        values = await collector.read_values([
            "ns=2;s=Temperature",
            "ns=2;s=Pressure",
        ])
        print(f"Values: {values}")
    finally:
        await collector.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
```

### Best Practices

- Use type hints (Python 3.9+)
- Use async/await for I/O-bound operations
- Use virtual environments (venv, poetry)
- Pin dependencies in requirements.txt
- Use logging module, not print()
- Run mypy and pylint before commit

---

## Rust

### When to Use

| Use Case | Suitability | Rationale |
|----------|-------------|-----------|
| Performance-critical | ✅ Excellent | Zero-cost abstractions |
| Memory-constrained | ✅ Excellent | No runtime, predictable |
| Systems programming | ✅ Excellent | Memory safety without GC |
| WebAssembly | ✅ Excellent | First-class WASM support |
| Long-running services | ✅ Good | No GC pauses |
| Rapid prototyping | ❌ Poor | Steep learning curve |
| Team familiarity | ⚠️ Varies | Rust expertise rare |

### Characteristics

**Strengths:**
- Memory safety without garbage collection
- Zero-cost abstractions
- Excellent performance
- Modern type system
- Fearless concurrency

**Weaknesses:**
- Steep learning curve (borrow checker)
- Longer development time
- Smaller ecosystem than Go/Python
- Compilation can be slow

### Code Pattern: High-Performance Data Processor

```rust
use std::sync::Arc;
use tokio::sync::mpsc;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TelemetryPoint {
    timestamp: i64,
    sensor_id: String,
    value: f64,
}

#[derive(Debug)]
struct TelemetryProcessor {
    buffer_size: usize,
}

impl TelemetryProcessor {
    fn new(buffer_size: usize) -> Self {
        Self { buffer_size }
    }

    async fn process_stream(
        &self,
        mut receiver: mpsc::Receiver<TelemetryPoint>,
    ) -> Vec<TelemetryPoint> {
        let mut buffer = Vec::with_capacity(self.buffer_size);
        
        while let Some(point) = receiver.recv().await {
            buffer.push(point);
            
            if buffer.len() >= self.buffer_size {
                // Process batch
                self.process_batch(&buffer).await;
                buffer.clear();
            }
        }
        
        buffer
    }

    async fn process_batch(&self, batch: &[TelemetryPoint]) {
        // High-performance batch processing
        let avg: f64 = batch.iter().map(|p| p.value).sum::<f64>() 
            / batch.len() as f64;
        println!("Batch average: {}", avg);
    }
}

#[tokio::main]
async fn main() {
    let (tx, rx) = mpsc::channel(1000);
    let processor = Arc::new(TelemetryProcessor::new(100));
    
    // Spawn processor
    let proc = processor.clone();
    let handle = tokio::spawn(async move {
        proc.process_stream(rx).await
    });
    
    // Send test data
    for i in 0..500 {
        tx.send(TelemetryPoint {
            timestamp: i,
            sensor_id: "sensor-1".to_string(),
            value: i as f64 * 0.1,
        }).await.unwrap();
    }
    
    drop(tx); // Signal completion
    let _ = handle.await;
}
```

### Best Practices

- Embrace the borrow checker (don't fight it)
- Use `Result<T, E>` for error handling
- Prefer `&str` over `String` for function parameters
- Use `cargo clippy` for linting
- Use `cargo fmt` for formatting
- Consider `tokio` for async runtime

---

## PowerShell

### When to Use

| Use Case | Suitability | Rationale |
|----------|-------------|-----------|
| Windows automation | ✅ Excellent | Native OS integration |
| Azure management | ✅ Excellent | Az module, ARM integration |
| Active Directory | ✅ Excellent | Native cmdlets |
| System administration | ✅ Excellent | WMI, registry, services |
| Cross-platform scripts | ✅ Good | PowerShell Core |
| CI/CD pipelines | ✅ Good | Azure DevOps native |
| High-performance | ❌ Poor | Interpreted, overhead |
| Containers | ⚠️ Okay | Image size, startup time |

### Characteristics

**Strengths:**
- Deep Windows integration
- Object-oriented pipeline
- Excellent Azure integration
- Rich ecosystem (PSGallery)
- Consistent verb-noun naming

**Weaknesses:**
- Slower than compiled languages
- Verbose syntax
- Less portable than Python
- Limited concurrency support

### Code Pattern: Azure Resource Management

```powershell
<#
.SYNOPSIS
    Manages Azure resources for IPC Platform.

.DESCRIPTION
    Provides functions for creating and managing Azure
    resources required by the IPC Platform.
#>

#Requires -Modules Az.Accounts, Az.Resources, Az.ContainerRegistry

function New-IPCPlatformResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory)]
        [string]$Location,
        
        [Parameter()]
        [hashtable]$Tags = @{}
    )
    
    begin {
        # Verify Azure connection
        $context = Get-AzContext
        if (-not $context) {
            throw "Not connected to Azure. Run Connect-AzAccount first."
        }
        Write-Verbose "Using subscription: $($context.Subscription.Name)"
    }
    
    process {
        # Create resource group
        $rg = New-AzResourceGroup `
            -Name $ResourceGroupName `
            -Location $Location `
            -Tag $Tags `
            -Force
        
        Write-Output "Created resource group: $($rg.ResourceGroupName)"
        
        # Create container registry
        $acrName = "acr$($ResourceGroupName -replace '-','')$(Get-Random -Maximum 9999)"
        $acr = New-AzContainerRegistry `
            -ResourceGroupName $ResourceGroupName `
            -Name $acrName `
            -Sku Basic `
            -Location $Location
        
        Write-Output "Created ACR: $($acr.LoginServer)"
        
        return @{
            ResourceGroup = $rg
            ContainerRegistry = $acr
        }
    }
    
    end {
        Write-Verbose "Resource creation complete"
    }
}

function Get-IPCPlatformHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName
    )
    
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    
    foreach ($resource in $resources) {
        $health = @{
            Name = $resource.Name
            Type = $resource.ResourceType
            Status = "Unknown"
        }
        
        # Check specific resource types
        switch -Wildcard ($resource.ResourceType) {
            "*containerRegistries" {
                $acr = Get-AzContainerRegistry `
                    -ResourceGroupName $ResourceGroupName `
                    -Name $resource.Name
                $health.Status = $acr.ProvisioningState
            }
            "*iotHubs" {
                $hub = Get-AzIotHub `
                    -ResourceGroupName $ResourceGroupName `
                    -Name $resource.Name
                $health.Status = $hub.Properties.State
            }
        }
        
        [PSCustomObject]$health
    }
}

# Export functions
Export-ModuleMember -Function New-IPCPlatformResources, Get-IPCPlatformHealth
```

### Best Practices

- Use approved verbs (Get, Set, New, Remove, etc.)
- Use `[CmdletBinding()]` for advanced function features
- Use `Write-Verbose` for debugging output
- Use `try/catch` for error handling
- Use parameter validation attributes
- Use `-WhatIf` and `-Confirm` for destructive operations

---

## Selection Decision Tree

```
START
  │
  ├─ Is this Windows/Azure automation?
  │   └─ Yes → PowerShell
  │
  ├─ Is performance critical (microseconds matter)?
  │   └─ Yes → Is team Rust-proficient?
  │            ├─ Yes → Rust
  │            └─ No → Go
  │
  ├─ Is this data processing/ML?
  │   └─ Yes → Python
  │
  ├─ Is this a Kubernetes operator/controller?
  │   └─ Yes → Go
  │
  ├─ Is this a CLI tool?
  │   └─ Yes → Go (or Rust for extreme performance)
  │
  ├─ Is this a quick automation script?
  │   └─ Yes → Python or PowerShell (based on target OS)
  │
  └─ Default → Go (best overall for cloud-native)
```

---

## IPC Platform Language Usage

| Component | Language | Rationale |
|-----------|----------|-----------|
| Workload containers | Python | OPC-UA library, rapid development |
| Build scripts | PowerShell | Windows + Azure DevOps native |
| Deployment automation | PowerShell | Azure integration |
| CLI tools | Go | Cross-platform, single binary |
| Performance-critical | Rust | Zero-cost abstractions |
| Infrastructure-as-Code | HCL (Terraform) | Domain-specific |
