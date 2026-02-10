variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "location" {
  type        = string
  description = "Azure Region"
  default     = "centralus"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
  default     = "dev"
}

variable "resource_prefix" {
  type        = string
  description = "Prefix for all resources (e.g., ipc-dmc-dev)"
}
