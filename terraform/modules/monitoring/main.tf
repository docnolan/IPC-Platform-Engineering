resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
}

resource "azurerm_portal_dashboard" "factory_overview" {
  name                = var.dashboard_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags = {
    source = "terraform"
  }

  dashboard_properties = templatefile("${path.module}/../../../observability/dashboards/factory-overview.json", {
    subscription_id = data.azurerm_client_config.current.subscription_id
    resource_group  = var.resource_group_name
    workspace_name  = azurerm_log_analytics_workspace.main.name
  })
}

data "azurerm_client_config" "current" {}

