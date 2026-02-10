<#
.SYNOPSIS
    Creates a new IPC Platform workload with all required files.

.DESCRIPTION
    This script scaffolds a complete workload including:
    - Docker directory with Dockerfile, azure-pipelines.yml, .trivyignore
    - Kubernetes manifests with deployment.yaml and kustomization.yaml
    - Updates parent kustomization.yaml automatically

.PARAMETER Name
    The name of the workload (lowercase, hyphenated, e.g., "my-workload")

.EXAMPLE
    .\New-Workload.ps1 -Name "edge-analytics"

.NOTES
    CMMC Level 2 Compliant - Implements NIST 800-171 Control 3.4.1 (Baseline Configurations)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-z][a-z0-9-]*[a-z0-9]$")]
    [string]$Name
)

$ErrorActionPreference = "Stop"

# Configuration
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DockerDir = Join-Path $RepoRoot "docker" $Name
$K8sDir = Join-Path $RepoRoot "kubernetes\workloads" $Name
$AcrName = "<your-acr-name>"

Write-Host "Creating workload: $Name" -ForegroundColor Cyan

# Validate workload doesn't already exist
if (Test-Path $DockerDir) {
    Write-Error "Docker directory already exists: $DockerDir"
    exit 1
}

if (Test-Path $K8sDir) {
    Write-Error "Kubernetes directory already exists: $K8sDir"
    exit 1
}

# Create Docker directory
New-Item -ItemType Directory -Path $DockerDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DockerDir "src") -Force | Out-Null

# Create Dockerfile
$Dockerfile = @"
# IPC Platform Workload: $Name
# Generated: $(Get-Date -Format "yyyy-MM-dd")
# NIST 800-171 Control 3.14.1 - Secure Base Image

FROM python:3.11-slim-bookworm

# Security: Non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY src/ ./

# Security hardening
RUN apt-get update && apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

USER appuser

# Health check endpoint
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "main.py"]
"@
Set-Content (Join-Path $DockerDir "Dockerfile") $Dockerfile

# Create requirements.txt
Set-Content (Join-Path $DockerDir "requirements.txt") "flask>=2.0.0`nrequests>=2.28.0"

# Create placeholder main.py
$MainPy = @"
"""
IPC Platform Workload: $Name
Generated scaffold - customize for your use case.
"""
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "workload": "$Name"})

@app.route('/')
def index():
    return jsonify({"message": "Hello from $Name"})

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
"@
Set-Content (Join-Path $DockerDir "src\main.py") $MainPy

# Create azure-pipelines.yml
$Pipeline = @"
name: `$(Major).`$(Minor).`$(Rev)

trigger:
  branches:
    include:
      - main
  paths:
    include:
      - docker/$Name/**
      - pipelines/templates/docker-build-scan-sign.yml

variables:
  - name: Major
    value: 1
  - name: Minor
    value: 0
  - name: Rev
    value: `$[counter(format('{0}.{1}', variables['Major'], variables['Minor']), 0)]
  - name: workloadName
    value: 'dmc/$Name'
  - name: dockerContext
    value: 'docker/$Name'
  - group: Security-Keys

pool:
  vmImage: 'ubuntu-latest'

jobs:
  - job: BuildAndDeliver
    displayName: 'Build, Scan, Sign, Push'
    steps:
      - task: DownloadSecureFile@1
        name: cosignKey
        displayName: 'Download Cosign Private Key'
        inputs:
          secureFile: 'cosign.key'

      - template: ../../pipelines/templates/docker-build-scan-sign.yml
        parameters:
          workloadName: `$(workloadName)
          dockerContext: `$(dockerContext)
          imageTag: 'v`$(Major).`$(Minor).`$(Rev)'
          cosignKeyPath: `$(cosignKey.secureFilePath)
"@
Set-Content (Join-Path $DockerDir "azure-pipelines.yml") $Pipeline

# Create .trivyignore
$Trivyignore = @"
# Risk-accepted CVEs for $Name
# Reference: docs/security/risk-register.md

# RR-001: CVE-2025-7458 - sqlite3 integer overflow (no fix available)
CVE-2025-7458

# RR-002: CVE-2023-45853 - zlib/minizip (will not fix)
CVE-2023-45853
"@
Set-Content (Join-Path $DockerDir ".trivyignore") $Trivyignore

Write-Host "  Created Docker files" -ForegroundColor Green

# Create Kubernetes directory
New-Item -ItemType Directory -Path $K8sDir -Force | Out-Null

# Create deployment.yaml
$Deployment = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $Name
  namespace: dmc-workloads
  labels:
    app.kubernetes.io/name: $Name
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/managed-by: Flux
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: $Name
  template:
    metadata:
      labels:
        app.kubernetes.io/name: $Name
        app.kubernetes.io/version: "1.0.0"
        app.kubernetes.io/managed-by: Flux
    spec:
      imagePullSecrets:
        - name: acr-pull-secret
      containers:
        - name: $Name
          image: $AcrName.azurecr.io/dmc/${Name}:v1.0.0 # {"`$imagepolicy": "flux-system:$Name"}
          imagePullPolicy: Always
          securityContext:
            runAsUser: 1000
            runAsGroup: 3000
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
          ports:
            - containerPort: 8080
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 2
            periodSeconds: 5
          volumeMounts:
            - name: tmp-volume
              mountPath: /tmp
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "200m"
      volumes:
        - name: tmp-volume
          emptyDir: {}
"@
Set-Content (Join-Path $K8sDir "deployment.yaml") $Deployment

# Create kustomization.yaml
$Kustomization = @"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
"@
Set-Content (Join-Path $K8sDir "kustomization.yaml") $Kustomization

Write-Host "  Created Kubernetes manifests" -ForegroundColor Green

# Update parent kustomization.yaml
$ParentKustomization = Join-Path $RepoRoot "kubernetes\workloads\kustomization.yaml"
$Content = Get-Content $ParentKustomization -Raw
if ($Content -notmatch "- $Name/") {
    $Content = $Content.TrimEnd() + "`n  - $Name/`n"
    Set-Content $ParentKustomization $Content
    Write-Host "  Updated parent kustomization.yaml" -ForegroundColor Green
}

# Add to Flux image automation
$ImageReposFile = Join-Path $RepoRoot "kubernetes\flux-system\image-automation\image-repositories.yaml"
$ImagePoliciesFile = Join-Path $RepoRoot "kubernetes\flux-system\image-automation\image-policies.yaml"

if (Test-Path $ImageReposFile) {
    $RepoEntry = @"

---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: $Name
  namespace: flux-system
spec:
  image: $AcrName.azurecr.io/dmc/$Name
  interval: 5m
  secretRef:
    name: acr-credentials
"@
    Add-Content $ImageReposFile $RepoEntry
    Write-Host "  Added ImageRepository" -ForegroundColor Green
}

if (Test-Path $ImagePoliciesFile) {
    $PolicyEntry = @"

---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: $Name
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: $Name
  policy:
    semver:
      range: ">=1.0.0"
"@
    Add-Content $ImagePoliciesFile $PolicyEntry
    Write-Host "  Added ImagePolicy" -ForegroundColor Green
}

Write-Host ""
Write-Host "Workload '$Name' created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Customize docker/$Name/src/main.py with your logic"
Write-Host "  2. Update docker/$Name/requirements.txt with dependencies"
Write-Host "  3. Commit and push to trigger pipeline"
Write-Host "  4. Register pipeline in Azure DevOps"
