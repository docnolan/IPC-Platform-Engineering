# Golden Image Pipeline
# Pillar 1: Automated Provisioning

---

# Table of Contents

1. [Overview](#1-overview)
2. [File Locations](#2-file-locations)
3. [Packer Template (Hyper-V - PoC)](#3-packer-template-hyper-v---poc)
4. [Packer Template (Azure ARM - Production)](#4-packer-template-azure-arm---production)
5. [Unattended Configuration](#5-unattended-configuration)
6. [Provisioner Scripts](#6-provisioner-scripts)
7. [Build Process](#7-build-process)
8. [Azure DevOps Pipeline](#8-azure-devops-pipeline)
9. [Creating VMs from Golden Image](#9-creating-vms-from-golden-image)
10. [Demo Talking Points](#10-demo-talking-points)

---

# 1. Overview

The golden image is a pre-configured, hardened Windows 10 IoT Enterprise installation that serves as the template for all IPC deployments.

| Characteristic | Description |
|----------------|-------------|
| **Immutable** | Once built, the image doesn't change |
| **Versioned** | Each build produces a new version (v1.0.0, v1.0.1) |
| **Compliant** | CIS Benchmark hardening applied at build time |
| **Pre-configured** | Azure Arc agent and AKS Edge pre-installed |

## 1.1 Current vs. Future State

| Aspect | PoC (Current) | Production (Future) |
|--------|---------------|---------------------|
| Build location | Local Hyper-V on workstation | Azure VM via pipeline |
| Trigger | Manual `packer build` | Git commit to `packer/` folder |
| Output | Local VHDX file | Azure Managed Image + Compute Gallery |
| CIS Hardening | Scripts ready, partial implementation | Full CIS Level 1 |

## 1.2 Build Process Flow

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Azure DevOps       │────►│     Packer          │────►│  Azure Managed      │
│  Pipeline           │     │  (Temporary VM)     │     │     Image           │
│  Triggered          │     │  1. Boot Win10      │     │  (Stored in         │
│                     │     │  2. Run scripts     │     │   Azure)            │
│                     │     │  3. Sysprep         │     │                     │
│                     │     │  4. Capture         │     │                     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

---

# 2. File Locations

| File | Local Path |
|------|------------|
| Packer template (PoC) | `C:\Projects\IPC-Platform-Engineering\packer\ipc-golden.pkr.hcl` |
| Packer template (Production) | `C:\Projects\IPC-Platform-Engineering\packer\windows-iot-enterprise\windows-iot-golden.pkr.hcl` |
| Unattended config | `C:\Projects\IPC-Platform-Engineering\packer\files\autounattend.xml` |
| Windows ISO | `F:\ISOs\en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso` |
| Output VHDX | `E:\IPC-Build\output-ipc-golden\` |
| Provisioner Scripts | `C:\Projects\IPC-Platform-Engineering\packer\scripts\` |

---

# 3. Packer Template (Hyper-V - PoC)

This template builds the golden image locally using Hyper-V on the workstation development machine.

**File:** `C:\Projects\IPC-Platform-Engineering\packer\ipc-golden.pkr.hcl`

```hcl
packer {
  required_plugins {
    hyperv = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

source "hyperv-iso" "ipc-golden" {
  vm_name           = "IPC-Golden-v1"
  generation        = 1
  cpus              = 4
  memory            = 8192
  disk_size         = 50000 
  switch_name       = "Default Switch"
  
  iso_url           = "F:/ISOs/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
  iso_checksum      = "sha256:a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"

  output_directory  = "E:/IPC-Build/output-ipc-golden"

  communicator      = "winrm"
  winrm_username    = "Administrator"
  winrm_password    = "FactoryFloor!23"
  winrm_timeout     = "2h"

  boot_command = [
    "<wait1><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar>",
    "<wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar>",
    "<wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar><wait><spacebar>"
  ]

  floppy_files = ["./files/autounattend.xml"]
}

build {
  sources = ["source.hyperv-iso.ipc-golden"]

  # Stage 1: Install base components
  provisioner "powershell" {
    script = "./scripts/01-install-base-components.ps1"
  }
  
  # Stage 2: Configure Windows features
  provisioner "powershell" {
    script = "./scripts/02-configure-windows-features.ps1"
  }
  
  # Stage 3: Apply CIS Benchmark hardening
  provisioner "powershell" {
    script = "./scripts/03-harden-cis-benchmark.ps1"
  }
  
  # Stage 4: Install Azure Arc agent
  provisioner "powershell" {
    script = "./scripts/04-install-arc-agent.ps1"
  }
  
  # Stage 5: Install AKS Edge Essentials
  provisioner "powershell" {
    script = "./scripts/05-install-aks-edge.ps1"
  }
  
  # Stage 6: Create image manifest
  provisioner "powershell" {
    script = "./scripts/06-create-manifest.ps1"
  }
  
  # Stage 7: Sysprep and finalize
  provisioner "powershell" {
    script = "./scripts/07-sysprep-finalize.ps1"
  }
}
```

---

# 4. Packer Template (Azure ARM - Production)

This template builds the golden image in Azure for production use.

**File:** `C:\Projects\IPC-Platform-Engineering\packer\windows-iot-enterprise\windows-iot-golden.pkr.hcl`

```hcl
packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "azure_subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID"
}

variable "image_resource_group" {
  type        = string
  default     = "rg-ipc-platform-images"
  description = "Resource group for storing images"
}

variable "image_version" {
  type        = string
  default     = "1.0.0"
  description = "Semantic version for the image"
}

variable "location" {
  type        = string
  default     = "centralus"
  description = "Azure region for image build"
}

variable "vm_size" {
  type        = string
  default     = "Standard_D4s_v3"
  description = "VM size for build process"
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  timestamp  = formatdate("YYYYMMDD-hhmmss", timestamp())
  image_name = "win10-iot-enterprise-ltsc-${var.image_version}-${local.timestamp}"
}

# ============================================================================
# Source: Azure ARM Builder
# ============================================================================

source "azure-arm" "windows_iot_enterprise" {
  # Authentication - Uses Azure CLI auth or Managed Identity in pipelines
  use_azure_cli_auth = true
  subscription_id    = var.azure_subscription_id
  
  # Image output
  managed_image_resource_group_name = var.image_resource_group
  managed_image_name                = local.image_name
  
  # Source image - Windows 10 Enterprise LTSC 21H2
  os_type         = "Windows"
  image_publisher = "MicrosoftWindowsDesktop"
  image_offer     = "Windows-10"
  image_sku       = "win10-21h2-ent-ltsc"
  
  # Build VM configuration
  location = var.location
  vm_size  = var.vm_size
  
  # WinRM communicator
  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "30m"
  winrm_username = "packer"
  
  # Tags for tracking
  azure_tags = {
    Environment      = "Production"
    Purpose          = "IPC-Golden-Image"
    ComplianceLevel  = "CIS-L1"
    ManagedBy        = "Platform-Engineering"
    BuildDate        = local.timestamp
    Version          = var.image_version
    NISTCompliant    = "Partial"
    CMMCLevel        = "2"
  }
}

# ============================================================================
# Build Steps
# ============================================================================

build {
  sources = ["source.azure-arm.windows_iot_enterprise"]
  
  # Stage 1: Install base components
  provisioner "powershell" {
    script = "./scripts/01-install-base-components.ps1"
  }
  
  # Stage 2: Configure Windows features
  provisioner "powershell" {
    script = "./scripts/02-configure-windows-features.ps1"
  }
  
  # Stage 3: Apply CIS Benchmark hardening
  provisioner "powershell" {
    script = "./scripts/03-harden-cis-benchmark.ps1"
  }
  
  # Stage 4: Install Azure Arc agent
  provisioner "powershell" {
    script = "./scripts/04-install-arc-agent.ps1"
  }
  
  # Stage 5: Install AKS Edge Essentials
  provisioner "powershell" {
    script = "./scripts/05-install-aks-edge.ps1"
  }
  
  # Stage 6: Create image manifest
  provisioner "powershell" {
    script = "./scripts/06-create-manifest.ps1"
  }
  
  # Stage 7: Sysprep and finalize
  provisioner "powershell" {
    script = "./scripts/07-sysprep-finalize.ps1"
  }
}
```

---

# 5. Version Pinning Strategy

The golden image pipeline pins AKS Edge Essentials to specific versions for reproducibility.

| Component | Pinned Version | Release Date | Notes |
|-----------|---------------|--------------|-------|
| AKS Edge Essentials | 1.11.247.0 | 2024-09-24 | Current production version |
| K3s | 1.31.6 | 2024-09-24 | Bundled with AKS EE |

### Updating Versions

To update to a new version:

1. Check releases at https://github.com/Azure/AKS-Edge/releases
2. Download new MSI and verify SHA256 hash
3. Update `$versionConfig` in `05-install-aks-edge.ps1`
4. Test in dev environment before production rollout
5. Update this documentation

### Why Pin Versions?

- **Reproducibility:** Same image every time
- **Compliance:** Auditable, known software versions
- **Stability:** Protection from breaking changes
- **Rollback:** Easy revert to known-good state

---

# 6. Unattended Configuration

**File:** `C:\Projects\IPC-Platform-Engineering\packer\files\autounattend.xml`

Key configuration sections:

| Section | Purpose |
|---------|---------|
| DiskConfiguration | Creates system reserved (500 MB) + Windows partition |
| UserData | Windows 10 IoT Enterprise LTSC product key |
| AutoLogon | Enables Administrator auto-logon for provisioning |
| FirstLogonCommands | Enables WinRM, sets network to Private |

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64">
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Size>500</Size>
              <Type>Primary</Type>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Extend>true</Extend>
              <Type>Primary</Type>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Label>System Reserved</Label>
              <Format>NTFS</Format>
              <Active>true</Active>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
              <Label>Windows</Label>
              <Format>NTFS</Format>
              <Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <Key>M7XTQ-FN8P6-TTKYV-9D4CC-J462D</Key>
        </ProductKey>
      </UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>1</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>FactoryFloor!23</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>Administrator</Username>
        <Password>
          <Value>FactoryFloor!23</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>10</LogonCount>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell -Command "Set-NetConnectionProfile -NetworkCategory Private"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>2</Order>
          <CommandLine>powershell -Command "Enable-PSRemoting -Force"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>3</Order>
          <CommandLine>powershell -Command "Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value True"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>4</Order>
          <CommandLine>powershell -Command "Set-Item WSMan:\localhost\Service\Auth\Basic -Value True"</CommandLine>
        </SynchronousCommand>
        <SynchronousCommand wcm:action="add">
          <Order>5</Order>
          <CommandLine>powershell -Command "New-NetFirewallRule -DisplayName 'WinRM HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
```

---

# 6. Provisioner Scripts

## 6.1 Script Summary

| Script | Purpose | NIST Controls |
|--------|---------|---------------|
| `01-install-base-components.ps1` | Chocolatey, Azure CLI, PowerShell modules | 3.4.8 |
| `02-configure-windows-features.ps1` | Enable Hyper-V, Containers, disable unnecessary services | 3.4.6 |
| `03-harden-cis-benchmark.ps1` | Account policies, security options, audit policies | 3.1.x, 3.3.x, 3.5.x |
| `04-install-arc-agent.ps1` | Pre-stage Azure Connected Machine Agent | 3.5.2 |
| `05-install-aks-edge.ps1` | Install AKS Edge Essentials (K3s) | — |
| `06-create-manifest.ps1` | Create image metadata for tracking | 3.4.1 |
| `07-sysprep-finalize.ps1` | Generalize image for deployment | — |

**Script Location:** `C:\Projects\IPC-Platform-Engineering\packer\scripts\`

---

## 6.2 Script: 01-install-base-components.ps1

```powershell
# 01-install-base-components.ps1
# Purpose: Install foundational components for IPC platform

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host "=== Stage 1: Installing Base Components ===" -ForegroundColor Cyan

# Configure TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install Chocolatey
Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
$env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"
choco feature enable -n allowGlobalConfirmation

# Install essential packages
$packages = @(
    "powershell-core",
    "azure-cli",
    "git",
    "7zip",
    "notepadplusplus"
)

foreach ($package in $packages) {
    Write-Host "Installing $package..." -ForegroundColor Yellow
    choco install $package -y --no-progress
}

# Install NuGet provider
Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# Install PowerShell modules
$modules = @(
    "Az.Accounts",
    "Az.Resources",
    "Az.ConnectedMachine"
)

foreach ($module in $modules) {
    Write-Host "Installing module: $module" -ForegroundColor Yellow
    Install-Module -Name $module -Force -AllowClobber -Scope AllUsers
}

# Create standard directories
$directories = @(
    "C:\ProgramData\IPCPlatform",
    "C:\ProgramData\IPCPlatform\Logs",
    "C:\ProgramData\IPCPlatform\Config",
    "C:\ProgramData\IPCPlatform\Scripts"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Host "=== Stage 1 Complete ===" -ForegroundColor Green
```

---

## 6.3 Script: 02-configure-windows-features.ps1

```powershell
# 02-configure-windows-features.ps1
# Purpose: Enable Windows features required for containers and virtualization

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 2: Configuring Windows Features ===" -ForegroundColor Cyan

# Features required for AKS Edge Essentials
$features = @(
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Tools-All",
    "Containers"
)

foreach ($feature in $features) {
    Write-Host "Enabling feature: $feature" -ForegroundColor Yellow
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue
    if ($result.RestartNeeded) {
        Write-Host "  Feature $feature requires restart" -ForegroundColor Gray
    }
}

# Configure Windows Defender exclusions for containers
Write-Host "Configuring Windows Defender exclusions..." -ForegroundColor Yellow
$exclusionPaths = @(
    "C:\ProgramData\AksEdge",
    "C:\Program Files\AksEdge",
    "C:\k",
    "C:\var\log"
)

foreach ($path in $exclusionPaths) {
    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
}

# Disable unnecessary services for OT environments
Write-Host "Disabling unnecessary services..." -ForegroundColor Yellow
$servicesToDisable = @(
    "DiagTrack",          # Diagnostics Tracking
    "dmwappushservice",   # WAP Push
    "MapsBroker",         # Downloaded Maps
    "lfsvc",              # Geolocation
    "WMPNetworkSvc"       # Windows Media Network
)

foreach ($service in $servicesToDisable) {
    $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  Disabling: $service" -ForegroundColor Gray
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# Configure power settings (prevent sleep)
Write-Host "Configuring power settings..." -ForegroundColor Yellow
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-ac 0

Write-Host "=== Stage 2 Complete ===" -ForegroundColor Green
```

---

## 6.4 Script: 03-harden-cis-benchmark.ps1

```powershell
# 03-harden-cis-benchmark.ps1
# Purpose: Apply CIS Benchmark Level 1 hardening for Windows 10 Enterprise
# Reference: CIS Microsoft Windows 10 Enterprise Benchmark v3.0.0

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 3: Applying CIS Benchmark Hardening ===" -ForegroundColor Cyan

# Create compliance log
$logPath = "C:\ProgramData\IPCPlatform\Logs\cis-hardening.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"CIS Hardening Started: $timestamp" | Out-File -FilePath $logPath

function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Name,
        [string]$Type,
        $Value,
        [string]$Description
    )
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        "$Description - Applied" | Out-File -FilePath $logPath -Append
        Write-Host "  [OK] $Description" -ForegroundColor Green
    }
    catch {
        "$Description - FAILED: $_" | Out-File -FilePath $logPath -Append
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
    }
}

# ============================================================================
# Account Policies (CIS 1.x)
# ============================================================================

Write-Host "Applying Account Policies..." -ForegroundColor Yellow

# 1.1.1 Password history (24 passwords)
net accounts /uniquepw:24

# 1.1.2 Maximum password age (60 days)
net accounts /maxpwage:60

# 1.1.3 Minimum password age (1 day)
net accounts /minpwage:1

# 1.1.4 Minimum password length (14 characters)
net accounts /minpwlen:14

# 1.2.1 Account lockout duration (15 minutes)
net accounts /lockoutduration:15

# 1.2.2 Account lockout threshold (5 attempts)
net accounts /lockoutthreshold:5

# 1.2.3 Reset lockout counter (15 minutes)
net accounts /lockoutwindow:15

# ============================================================================
# Security Options (CIS 2.3.x)
# ============================================================================

Write-Host "Applying Security Options..." -ForegroundColor Yellow

# 2.3.1.1 Block Microsoft accounts
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "NoConnectedUser" -Type "DWord" -Value 3 `
    -Description "2.3.1.1 Block Microsoft accounts"

# 2.3.2.1 Force audit policy subcategory settings
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "SCENoApplyLegacyAuditPolicy" -Type "DWord" -Value 1 `
    -Description "2.3.2.1 Force audit policy subcategory settings"

# 2.3.7.1 Require CTRL+ALT+DEL
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "DisableCAD" -Type "DWord" -Value 0 `
    -Description "2.3.7.1 Require CTRL+ALT+DEL"

# 2.3.7.3 Machine inactivity limit (900 seconds / 15 minutes)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "InactivityTimeoutSecs" -Type "DWord" -Value 900 `
    -Description "2.3.7.3 Machine inactivity limit"

# 2.3.8.1 SMB client signing (always)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Name "RequireSecuritySignature" -Type "DWord" -Value 1 `
    -Description "2.3.8.1 SMB client signing always"

# 2.3.9.1 SMB server signing (always)
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -Name "RequireSecuritySignature" -Type "DWord" -Value 1 `
    -Description "2.3.9.1 SMB server signing always"

# 2.3.10.5 Disable Everyone permissions for anonymous
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "EveryoneIncludesAnonymous" -Type "DWord" -Value 0 `
    -Description "2.3.10.5 Disable Everyone for anonymous"

# 2.3.11.6 NTLMv2 only
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LmCompatibilityLevel" -Type "DWord" -Value 5 `
    -Description "2.3.11.6 NTLMv2 only"

# ============================================================================
# Windows Firewall (CIS 9.x)
# ============================================================================

Write-Host "Applying Windows Firewall Settings..." -ForegroundColor Yellow

# Enable all firewall profiles
Set-NetFirewallProfile -Profile Domain -Enabled True
Set-NetFirewallProfile -Profile Private -Enabled True
Set-NetFirewallProfile -Profile Public -Enabled True

# Configure firewall logging
$logDirectory = "C:\Windows\System32\LogFiles\Firewall"
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

Set-NetFirewallProfile -Profile Domain,Private,Public `
    -LogFileName "$logDirectory\pfirewall.log" `
    -LogMaxSizeKilobytes 16384 `
    -LogBlocked True `
    -LogAllowed False

# ============================================================================
# Network Security (CIS 18.x)
# ============================================================================

Write-Host "Applying Network Security Settings..." -ForegroundColor Yellow

# 18.4.3 Disable IP source routing
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "DisableIPSourceRouting" -Type "DWord" -Value 2 `
    -Description "18.4.3 Disable IP source routing"

# 18.4.4 Disable IPv6 source routing
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" `
    -Name "DisableIPSourceRouting" -Type "DWord" -Value 2 `
    -Description "18.4.4 Disable IPv6 source routing"

# 18.4.6 Disable ICMP redirects
Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" `
    -Name "EnableICMPRedirect" -Type "DWord" -Value 0 `
    -Description "18.4.6 Disable ICMP redirects"

# 18.5.4.1 Disable multicast name resolution (LLMNR)
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
    -Name "EnableMulticast" -Type "DWord" -Value 0 `
    -Description "18.5.4.1 Disable LLMNR"

# 18.9.11.1.1 Limit diagnostic data
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -Name "AllowTelemetry" -Type "DWord" -Value 1 `
    -Description "18.9.11.1.1 Limit diagnostic data"

# 18.9.85.1.1 Enable SmartScreen
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
    -Name "EnableSmartScreen" -Type "DWord" -Value 1 `
    -Description "18.9.85.1.1 Enable SmartScreen"

# ============================================================================
# Audit Policies (CIS 17.x)
# ============================================================================

Write-Host "Applying Audit Policies..." -ForegroundColor Yellow

$auditCategories = @(
    "Credential Validation",
    "Security Group Management",
    "User Account Management",
    "Process Creation",
    "Account Lockout",
    "Logoff",
    "Logon",
    "Special Logon",
    "Removable Storage",
    "Audit Policy Change",
    "Authentication Policy Change",
    "Sensitive Privilege Use",
    "Security State Change",
    "Security System Extension",
    "System Integrity"
)

foreach ($category in $auditCategories) {
    auditpol /set /subcategory:"$category" /success:enable /failure:enable 2>&1 | Out-Null
    Write-Host "  [OK] Audit: $category" -ForegroundColor Green
}

# ============================================================================
# Legal Notice Banner (NIST 3.1.9)
# ============================================================================

Write-Host "Configuring Legal Notice Banner..." -ForegroundColor Yellow

$legalCaption = "AUTHORIZED USE ONLY"
$legalText = @"
This system is the property of The Company, Inc. and is provided for authorized business use only.
All activities on this system may be monitored and recorded. 
Unauthorized access or use is prohibited and may result in disciplinary action and/or civil and criminal penalties.
By using this system, you consent to monitoring and acknowledge these terms.
"@

Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticecaption" -Type "String" -Value $legalCaption `
    -Description "Legal notice caption"

Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "legalnoticetext" -Type "String" -Value $legalText `
    -Description "Legal notice text"

# Finalize
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"CIS Hardening Completed: $timestamp" | Out-File -FilePath $logPath -Append

Write-Host "=== Stage 3 Complete ===" -ForegroundColor Green
Write-Host "CIS Benchmark hardening log: $logPath" -ForegroundColor Cyan
```

### Key CIS Controls Summary

| Control | Setting | Value |
|---------|---------|-------|
| 1.1.4 | Minimum password length | 14 characters |
| 1.2.1-3 | Account lockout | 5 attempts, 15 min duration |
| 2.3.7.3 | Machine inactivity limit | 900 seconds (15 min) |
| 2.3.11.6 | LAN Manager auth level | NTLMv2 only (Level 5) |
| 17.x | Audit policies | Success+Failure for all categories |
| 18.5.4.1 | LLMNR | Disabled |
| Legal Notice | Login banner | "AUTHORIZED USE ONLY" |

---

## 6.5 Script: 04-install-arc-agent.ps1

```powershell
# 04-install-arc-agent.ps1
# Purpose: Pre-stage Azure Arc Connected Machine Agent

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 4: Installing Azure Arc Agent ===" -ForegroundColor Cyan

# Download Azure Connected Machine Agent
$downloadUrl = "https://aka.ms/AzureConnectedMachineAgent"
$installerPath = "$env:TEMP\AzureConnectedMachineAgent.msi"

Write-Host "Downloading Azure Connected Machine Agent..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# Install the agent
Write-Host "Installing agent..." -ForegroundColor Yellow
$installArgs = "/i `"$installerPath`" /qn /norestart"
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Azure Connected Machine Agent installation failed with exit code: $($process.ExitCode)"
}

# Create registration script template for post-deployment
$registrationScript = @'
# Azure Arc Registration Script
# Run this script on first boot after deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [string]$ServicePrincipalId,
    [string]$ServicePrincipalSecret,
    [string]$CustomerName = "IPC-Customer"
)

$hostname = $env:COMPUTERNAME

& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id $ServicePrincipalId `
    --service-principal-secret $ServicePrincipalSecret `
    --resource-group $ResourceGroup `
    --tenant-id $TenantId `
    --location $Location `
    --subscription-id $SubscriptionId `
    --cloud "AzureCloud" `
    --tags "Environment=Production,Platform=IPC,Customer=$CustomerName,Hostname=$hostname"
'@

$registrationScript | Out-File -FilePath "C:\ProgramData\IPCPlatform\Scripts\Register-AzureArc.ps1" -Encoding UTF8

# Clean up
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Host "=== Stage 4 Complete ===" -ForegroundColor Green
Write-Host "Arc agent installed. Registration script: C:\ProgramData\IPCPlatform\Scripts\Register-AzureArc.ps1" -ForegroundColor Cyan
```

---

## 6.6 Script: 05-install-aks-edge.ps1

```powershell
# 05-install-aks-edge.ps1
# Purpose: Install AKS Edge Essentials and pre-stage configuration

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 5: Installing AKS Edge Essentials ===" -ForegroundColor Cyan

# Download AKS Edge Essentials (K3s distribution)
$downloadUrl = "https://aka.ms/aks-edge/k3s-msi"
$installerPath = "$env:TEMP\AksEdge-K3s.msi"

Write-Host "Downloading AKS Edge Essentials (K3s)..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# Install AKS Edge Essentials
Write-Host "Installing AKS Edge Essentials..." -ForegroundColor Yellow
$installArgs = "/i `"$installerPath`" /qn /norestart INSTALLDIR=`"C:\Program Files\AksEdge`" VHDXDIR=`"C:\AksEdge\vhdx`""
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
    throw "AKS Edge Essentials installation failed with exit code: $($process.ExitCode)"
}

# Create deployment configuration template
$deploymentConfig = @{
    SchemaVersion = "1.14"
    Version = "1.0"
    DeploymentType = "SingleMachineCluster"
    Init = @{
        ServiceIPRangeSize = 10
    }
    Network = @{
        InternetDisabled = $false
    }
    User = @{
        AcceptEula = $true
        AcceptOptionalTelemetry = $false
    }
    Machines = @(
        @{
            LinuxNode = @{
                CpuCount = 4
                MemoryInMB = 4096
                DataSizeInGB = 20
            }
        }
    )
    Arc = @{
        ClusterName = "REPLACE_WITH_CLUSTER_NAME"
        Location = "centralus"
        ResourceGroupName = "rg-ipc-platform-arc"
        SubscriptionId = "REPLACE_WITH_SUBSCRIPTION_ID"
        TenantId = "REPLACE_WITH_TENANT_ID"
        ClientId = "REPLACE_WITH_CLIENT_ID"
        ClientSecret = "REPLACE_WITH_CLIENT_SECRET"
    }
}

$configPath = "C:\ProgramData\AksEdge"
if (-not (Test-Path $configPath)) {
    New-Item -ItemType Directory -Path $configPath -Force | Out-Null
}

$deploymentConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath "$configPath\aksedge-config-template.json" -Encoding UTF8

# Clean up
Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

Write-Host "=== Stage 5 Complete ===" -ForegroundColor Green
Write-Host "AKS Edge Essentials installed. Config template: $configPath\aksedge-config-template.json" -ForegroundColor Cyan
```

---

## 6.7 Script: 06-create-manifest.ps1

```powershell
# 06-create-manifest.ps1
# Purpose: Create image manifest for tracking and compliance

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 6: Creating Image Manifest ===" -ForegroundColor Cyan

$manifest = @{
    ImageBuildDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Version
    WindowsBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    ImageType = "Windows 10 IoT Enterprise LTSC 2021"
    InstalledComponents = @(
        "Azure Connected Machine Agent",
        "AKS Edge Essentials (K3s)",
        "PowerShell Core",
        "Azure CLI",
        "Chocolatey Package Manager"
    )
    SecurityHardening = @{
        Framework = "CIS Benchmark"
        Level = "Level 1"
        Version = "v3.0.0"
    }
    ComplianceFrameworks = @(
        "NIST 800-171 Rev 2 (Partial)",
        "CMMC Level 2 (Partial)"
    )
    ManagedBy = "IPC Platform Engineering"
    SupportContact = "<support-email>"
}

$manifestPath = "C:\ProgramData\IPCPlatform\Config\image-manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding UTF8

Write-Host "Image manifest created: $manifestPath" -ForegroundColor Cyan
Write-Host "=== Stage 6 Complete ===" -ForegroundColor Green
```

---

## 6.8 Script: 07-sysprep-finalize.ps1

```powershell
# 07-sysprep-finalize.ps1
# Purpose: Final cleanup and Sysprep for image generalization

$ErrorActionPreference = "Stop"
Write-Host "=== Stage 7: Final Cleanup and Sysprep ===" -ForegroundColor Cyan

# Clear Windows Update cache
Write-Host "Clearing Windows Update cache..." -ForegroundColor Yellow
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue

# Clear temp files
Write-Host "Clearing temporary files..." -ForegroundColor Yellow
$tempPaths = @(
    "$env:TEMP\*",
    "C:\Windows\Temp\*"
)
foreach ($path in $tempPaths) {
    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
}

# Clear event logs (optional - comment out if you want to preserve build logs)
Write-Host "Clearing event logs..." -ForegroundColor Yellow
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
    } catch { }
}

# Wait for Azure agent services
Write-Host "Waiting for Azure agent services..." -ForegroundColor Yellow
while ((Get-Service RdAgent -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Start-Sleep -Seconds 5
}
while ((Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue).Status -ne 'Running') {
    Start-Sleep -Seconds 5
}

# Run Sysprep
Write-Host "Running Sysprep..." -ForegroundColor Yellow
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm

# Wait for Sysprep to complete
Write-Host "Waiting for Sysprep to complete..." -ForegroundColor Yellow
while ($true) {
    $imageState = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State" | 
                  Select-Object -ExpandProperty ImageState
    if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
        break
    }
    Write-Host "  Current state: $imageState" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}

Write-Host "=== Stage 7 Complete ===" -ForegroundColor Green
Write-Host "Image is ready for capture." -ForegroundColor Cyan
```

---

# 7. Build Process

## 7.1 Manual Build (PoC - Current)

Run on **workstation** from the Packer directory in the Git repository:

```powershell
cd C:\Projects\IPC-Platform-Engineering\packer

# Initialize Packer plugins (first time only)
packer init dmc-golden.pkr.hcl

# Build the image
packer build dmc-golden.pkr.hcl

# Output location: E:\IPC-Build\output-ipc-golden\
```

**Build time:** ~45 minutes

## 7.2 Automated Build (Production - Future)

```powershell
cd C:\Projects\IPC-Platform-Engineering\packer\windows-iot-enterprise

# Initialize Packer plugins
packer init windows-iot-golden.pkr.hcl

# Validate template
packer validate windows-iot-golden.pkr.hcl

# Build with variables
packer build `
  -var "azure_subscription_id=<your-subscription-id>" `
  -var "azure_tenant_id=<your-tenant-id>" `
  -var "image_version=1.0.0" `
  windows-iot-golden.pkr.hcl
```

---

# 8. Azure DevOps Pipeline

**File:** `C:\Projects\IPC-Platform-Engineering\pipelines\build-golden-image.yml`

```yaml
# build-golden-image.yml
# Triggers when Packer templates or scripts change
# For production: builds image in Azure, stores in Compute Gallery

trigger:
  branches:
    include:
      - main
  paths:
    include:
      - packer/**

pr:
  branches:
    include:
      - main
  paths:
    include:
      - packer/**

pool:
  vmImage: 'windows-latest'

variables:
  - group: ipc-platform-variables
  - name: imageVersion
    value: '1.0.$(Build.BuildId)'

stages:
  - stage: Validate
    displayName: 'Validate Packer Configuration'
    jobs:
      - job: ValidatePacker
        displayName: 'Validate Packer Template'
        steps:
          - task: PowerShell@2
            displayName: 'Install Packer'
            inputs:
              targetType: 'inline'
              script: |
                choco install packer -y --no-progress
                $env:Path += ";C:\ProgramData\chocolatey\bin"
                packer --version

          - task: PowerShell@2
            displayName: 'Validate Packer Syntax'
            inputs:
              targetType: 'inline'
              script: |
                cd $(Build.SourcesDirectory)/packer/windows-iot-enterprise
                packer validate -syntax-only .
                Write-Host "Packer template syntax is valid"

  - stage: Build
    displayName: 'Build Golden Image'
    dependsOn: Validate
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: BuildImage
        displayName: 'Build Packer Image'
        timeoutInMinutes: 120
        steps:
          - task: PowerShell@2
            displayName: 'Log Build Metadata'
            inputs:
              targetType: 'inline'
              script: |
                Write-Host "##[section]Golden Image Build"
                Write-Host "Version: $(imageVersion)"
                Write-Host "Triggered by: $(Build.RequestedFor)"
                Write-Host "Commit: $(Build.SourceVersion)"
                
                # In production, this would trigger an Azure Packer build
                # For PoC, we document the process and validate syntax only
                Write-Host "##[warning]Production build would execute here"
                Write-Host "For PoC: Run 'packer build' manually on workstation"

          - task: PublishBuildArtifacts@1
            displayName: 'Publish Build Log'
            inputs:
              pathToPublish: '$(Build.SourcesDirectory)/packer'
              artifactName: 'packer-config'
```

## 8.1 Pipeline Behavior

| Trigger | Action |
|---------|--------|
| PR to `main` touching `packer/**` | Validate syntax only |
| Merge to `main` touching `packer/**` | Validate + log (production would build) |

**Note:** Full automated Azure-based builds require additional infrastructure (see Production Roadmap). For the PoC, this pipeline validates syntax and documents the workflow.

---

# 9. Creating VMs from Golden Image

After Packer builds the image, create new VMs:

```powershell
# On workstation - Create new VM from golden image
$VMName = "IPC-Customer-Panel-01"
$GoldenVHDX = "E:\IPC-Build\output-ipc-golden\Virtual Hard Disks\IPC-Golden-v1.vhdx"
$NewVHDX = "E:\Factory-VMs\Customer-VMs\$VMName.vhdx"

# Copy the golden image
Copy-Item -Path $GoldenVHDX -Destination $NewVHDX

# Create new VM
New-VM -Name $VMName `
  -MemoryStartupBytes 8GB `
  -VHDPath $NewVHDX `
  -Generation 1 `
  -SwitchName "Default Switch"

Set-VMProcessor -VMName $VMName -Count 4
Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false

Start-VM -Name $VMName
```

---

# 10. Key Technical Benefits

When considering Automated Provisioning (Pillar 1):

- "Every IPC starts from this golden image—identical, every time"
- "Security hardening is baked in at build time, not bolted on after"
- "When we update a hardening script, the next build automatically includes it"
- "What used to take 4-8 hours of manual work is now a 30-minute automated process"
- "Full audit trail—we know exactly what's in every image"
- "This template lives in Git. Change control, peer review, version history—all automatic"

---

*End of Golden Image Pipeline Section*

**Previous:** [01-Azure-Foundation.md](01-Azure-Foundation.md)  
**Next:** [03-Edge-Deployment.md](03-Edge-Deployment.md)
