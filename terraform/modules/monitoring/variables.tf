variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "log_analytics_workspace_name" {
  type        = string
  description = "Name of the Log Analytics Workspace"
}

variable "retention_in_days" {
  type        = number
  description = "The workspace data retention in days"
  default     = 90
}

variable "dashboard_name" {
  type        = string
  description = "Name of the Factory Overview Dashboard"
  default     = "IPC-Factory-Overview"
}

