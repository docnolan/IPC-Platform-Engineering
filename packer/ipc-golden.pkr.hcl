packer {
  required_plugins {
    hyperv = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

source "hyperv-iso" "ipc-golden" {
  vm_name           = var.vm_name
  generation        = 1
  cpus              = var.cpus
  memory            = var.memory
  disk_size         = var.disk_size
  switch_name       = var.switch_name
  
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum

  output_directory  = var.output_directory

  communicator      = "winrm"
  winrm_username    = var.winrm_username
  winrm_password    = var.winrm_password
  winrm_timeout     = var.winrm_timeout

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
    environment_vars = [
      "ClusterName=${var.arc_cluster_name}",
      "SubscriptionId=${var.arc_subscription_id}",
      "TenantId=${var.arc_tenant_id}",
      "ClientId=${var.arc_client_id}",
      "ClientSecret=${var.arc_client_secret}"
    ]
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
