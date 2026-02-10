variable "name" {
  type        = string
  description = "Name of the Container Registry"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "sku" {
  type        = string
  description = "The SKU name of the container registry"
  default     = "Basic"
}

variable "admin_enabled" {
  type        = bool
  description = "Is the admin user enabled?"
  default     = true
}
