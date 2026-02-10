variable "vm_name" {
  type    = string
  default = "IPC-Factory-01"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "memory" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = number
  default = 50000
}

variable "switch_name" {
  type    = string
  default = "Default Switch"
}

variable "iso_url" {
  type    = string
  default = "F:/ISOs/en-us_windows_10_iot_enterprise_ltsc_2021_x64_dvd_257ad90f.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160"
}

variable "output_directory" {
  type    = string
  default = "E:/IPC-Build/output-ipc-golden"
}

variable "winrm_username" {
  type    = string
  default = "Administrator"
}

variable "winrm_password" {
  type      = string
  sensitive = true
  default   = "FactoryFloor!23"
}

variable "winrm_timeout" {
  type    = string
  default = "2h"
}

# Azure Arc Variables (Passed to provisioners)
variable "arc_cluster_name" {
  type    = string
  default = "aks-edge-ipc-factory-01"
}

variable "arc_subscription_id" {
  type    = string
}

variable "arc_tenant_id" {
  type    = string
}

variable "arc_resource_group" {
  type    = string
  default = "rg-ipc-platform-arc"
}

variable "arc_location" {
  type    = string
  default = "centralus"
}

variable "arc_client_id" {
  type      = string
  sensitive = true
}

variable "arc_client_secret" {
  type      = string
  sensitive = true
}
