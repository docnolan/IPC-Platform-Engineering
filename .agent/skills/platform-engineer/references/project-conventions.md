# Project Conventions

Comprehensive conventions for the IPC Platform Engineering project covering file organization, naming standards, coding patterns, and operational practices.

## Repository Structure

```
C:\Projects\IPC-Platform-Engineering\
├── .agent\                      # Agent skills and automation
│   └── skills\                  # Skill definitions
├── docker\                      # Container definitions
│   ├── <workload>\
│   │   ├── Dockerfile
│   │   ├── src\                 # Application source
│   │   └── requirements.txt     # Python dependencies
├── kubernetes\                  # Kubernetes manifests
│   ├── base\                    # Base configurations
│   ├── overlays\                # Environment-specific
│   │   ├── dev\
│   │   ├── staging\
│   │   └── production\
│   └── workloads\               # Workload deployments
│       └── <workload>\
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           └── kustomization.yaml
├── packer\                      # Golden image definitions
│   └── windows-iot-enterprise\
│       ├── *.pkr.hcl
│       └── scripts\
├── terraform\                   # Infrastructure-as-Code
│   ├── modules\                 # Reusable modules
│   └── environments\            # Environment configs
├── pipelines\                   # CI/CD definitions
│   ├── templates\               # Reusable templates
│   └── *.yml
├── scripts\                     # Operational scripts
│   ├── deployment\
│   ├── maintenance\
│   └── validation\
├── compliance\                  # Compliance artifacts
│   ├── nist-mapping\
│   └── evidence\
├── docs\                        # Documentation
│   ├── architecture\
│   │   └── decisions\           # ADRs
│   ├── runbooks\
│   └── wiki\
└── tests\                       # Test suites
    ├── unit\
    ├── integration\
    └── e2e\
```

## Naming Conventions

### Files and Directories

| Type | Convention | Example |
|------|------------|---------|
| Directories | lowercase-with-hyphens | `health-monitor/` |
| YAML files | lowercase-with-hyphens | `deployment.yaml` |
| PowerShell | PascalCase with verb-noun | `Invoke-PreflightCheck.ps1` |
| Python | lowercase_with_underscores | `health_collector.py` |
| Go | lowercase | `main.go` |
| Dockerfiles | `Dockerfile` (exact) | `Dockerfile` |
| Shell scripts | lowercase-with-hyphens | `setup-cluster.sh` |
| Documentation | Title-Case or lowercase | `README.md`, `SKILL.md` |

### Azure Resources

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| Resource Group | `rg-{project}-{purpose}` | `rg-ipc-platform-monitoring` |
| Container Registry | `acr{project}{random}` | `<your-acr-name>` |
| IoT Hub | `iothub-{project}-{random}` | `<your-iothub-name>` |
| Log Analytics | `law-{project}` | `<your-workspace-name>` |
| Key Vault | `kv-{project}-{env}` | `kv-ipc-platform-prod` |
| Storage Account | `st{project}{purpose}` | `stipcplatformbackup` |
| Virtual Network | `vnet-{project}-{region}` | `vnet-ipc-platform-centralus` |
| Arc Cluster | `aks-edge-{site}` | `<your-arc-cluster-name>` |

### Kubernetes Resources

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| Namespace | `{project}-{purpose}` | `dmc-workloads` |
| Deployment | `{workload-name}` | `health-monitor` |
| Service | `{workload-name}` | `health-monitor` |
| ConfigMap | `{workload-name}-config` | `health-monitor-config` |
| Secret | `{workload-name}-secrets` | `health-monitor-secrets` |
| ServiceAccount | `{workload-name}-sa` | `health-monitor-sa` |

### Container Images

```
{registry}/{namespace}/{image}:{tag}

Examples:
<your-acr-name>.azurecr.io/dmc/health-monitor:1.0.0
<your-acr-name>.azurecr.io/dmc/health-monitor:latest
<your-acr-name>.azurecr.io/dmc/health-monitor:42  (build number)
```

### Git Branches

| Type | Pattern | Example |
|------|---------|---------|
| Main branch | `main` | `main` |
| Feature | `feature/{ticket}-{description}` | `feature/123-add-anomaly-detection` |
| Bugfix | `fix/{ticket}-{description}` | `fix/456-memory-leak` |
| Release | `release/{version}` | `release/1.0.0` |
| Hotfix | `hotfix/{ticket}-{description}` | `hotfix/789-critical-patch` |

### Git Commits

Format: `{type}: {description}`

```
feat: Add anomaly detection workload
fix: Resolve memory leak in health monitor
docs: Update deployment runbook
refactor: Simplify gateway connection logic
chore: Update dependencies
ci: Add container scanning to pipeline
test: Add unit tests for data collector

# With scope
feat(gateway): Add retry logic for IoT Hub connection
fix(monitor): Handle null values in CPU metrics

# With work item reference
feat: Add log forwarder workload

Implements security event forwarding to Log Analytics.

- Captures Windows Security events
- Filters to relevant event IDs
- Batches uploads for efficiency

Refs: AB#123
```

## Code Standards

### PowerShell

```powershell
<#
.SYNOPSIS
    Brief description of script purpose.

.DESCRIPTION
    Detailed description of what the script does.

.PARAMETER ParameterName
    Description of parameter.

.EXAMPLE
    .\Script-Name.ps1 -Parameter Value
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RequiredParam,
    
    [ValidateSet("Option1", "Option2")]
    [string]$ChoiceParam = "Option1",
    
    [switch]$OptionalFlag
)

# Use approved verbs: Get, Set, New, Remove, Invoke, Start, Stop, etc.
# Use PascalCase for functions
# Use meaningful variable names
# Include error handling

function Get-Something {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        # Implementation
    }
    catch {
        Write-Error "Failed to get something: $_"
        throw
    }
}
```

### Python

```python
#!/usr/bin/env python3
"""
Module docstring describing purpose.

This module handles [specific functionality].
"""

import logging
from typing import Optional, Dict, Any

# Configure logging
logger = logging.getLogger(__name__)


class ClassName:
    """Class docstring describing purpose."""
    
    def __init__(self, param: str) -> None:
        """Initialize with parameter.
        
        Args:
            param: Description of parameter.
        """
        self.param = param
    
    def method_name(self, arg: str) -> Optional[Dict[str, Any]]:
        """Method docstring.
        
        Args:
            arg: Description of argument.
            
        Returns:
            Description of return value.
            
        Raises:
            ValueError: When arg is invalid.
        """
        try:
            # Implementation
            return {"result": arg}
        except Exception as e:
            logger.error(f"Error in method_name: {e}")
            raise


def main() -> None:
    """Main entry point."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    # Implementation


if __name__ == "__main__":
    main()
```

### Dockerfile

```dockerfile
# Use specific version tags, not 'latest'
FROM python:3.11-slim

# Labels for metadata
LABEL maintainer="platform-team@example.com"
LABEL version="1.0.0"
LABEL description="Brief description"

# Set working directory
WORKDIR /app

# Copy dependency files first (caching)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)"

# Set entrypoint
ENTRYPOINT ["python", "src/main.py"]
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workload-name
  namespace: dmc-workloads
  labels:
    app.kubernetes.io/name: workload-name
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: ipc-platform
    app.kubernetes.io/managed-by: flux
spec:
  replicas: 1
  selector:
    matchLabels:
      app: workload-name
  template:
    metadata:
      labels:
        app: workload-name
        app.kubernetes.io/name: workload-name
    spec:
      serviceAccountName: workload-name-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
        - name: workload-name
          image: <your-acr-name>.azurecr.io/dmc/workload-name:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: LOG_LEVEL
              value: "INFO"
            - name: SECRET_VALUE
              valueFrom:
                secretKeyRef:
                  name: workload-name-secrets
                  key: secret-key
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
      imagePullSecrets:
        - name: regcred
```

### Terraform

```hcl
# main.tf
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  backend "azurerm" {
    # Configure in environment
  }
}

# Use consistent naming
locals {
  project_name = "ipc-platform"
  environment  = var.environment
  
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

# Resources with clear naming
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.project_name}-${local.environment}"
  location = var.location
  tags     = local.common_tags
}

# Variables in variables.tf
variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Outputs in outputs.tf
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}
```

## Environment Variables

### Standard Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription | `8ebd8d6d-...` |
| `AZURE_TENANT_ID` | Azure AD tenant | `d3d4e5b9-...` |
| `LOG_ANALYTICS_WORKSPACE_ID` | Log Analytics workspace | `6554557e-...` |
| `IOT_HUB_CONNECTION_STRING` | IoT Hub connection | `HostName=...` |
| `ACR_LOGIN_SERVER` | Container registry | `<your-acr-name>.azurecr.io` |
| `LOG_LEVEL` | Logging verbosity | `INFO`, `DEBUG` |
| `ENVIRONMENT` | Deployment environment | `dev`, `prod` |

### Secrets (Never in Code)

- Use Kubernetes Secrets for workloads
- Use Azure Key Vault for infrastructure
- Use Workload Identity Federation where possible
- Use environment variables at runtime only

## Validation Commands

```powershell
# YAML syntax
kubectl apply --dry-run=client -f manifest.yaml

# Kubernetes manifests
kubectl diff -f manifest.yaml

# Terraform
terraform fmt -check
terraform validate

# Docker build
docker build --no-cache -t test:validation .

# PowerShell syntax
$null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content script.ps1 -Raw), [ref]$null)

# Python syntax
python -m py_compile script.py
```
