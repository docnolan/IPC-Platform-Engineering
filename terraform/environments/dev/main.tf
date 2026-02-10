resource "azurerm_resource_group" "acr" {
  name     = "rg-${var.resource_prefix}-acr"
  location = var.location
}

resource "azurerm_resource_group" "monitoring" {
  name     = "rg-${var.resource_prefix}-monitoring"
  location = var.location
}

module "acr" {
  source              = "../../modules/acr"
  name                = replace("acr${var.resource_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.acr.name
  location            = azurerm_resource_group.acr.location
  sku                 = "Basic"
  admin_enabled       = true
}

module "monitoring" {
  source                       = "../../modules/monitoring"
  log_analytics_workspace_name = "law-${var.resource_prefix}"
  resource_group_name          = azurerm_resource_group.monitoring.name
  location                     = azurerm_resource_group.monitoring.location
  retention_in_days            = 90
}
