terraform {
  backend "azurerm" {
    resource_group_name  = "rg-ipc-platform-tfstate"
    storage_account_name = "stipcplatformtfstate001"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
