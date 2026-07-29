# Simple configuration with only the necessary resources to store the Terraform state file

# Terraform block to set the Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
}

# Configure the Microsoft Azure Provider block
provider "azurerm" {
  resource_provider_registrations = "none" # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

# Resources to store remote tfstate

resource "azurerm_resource_group" "rg" {
  name     = "dib00016-githubactions-rg"
  location = "Canada Central"
}

resource "azurerm_storage_account" "sa" {
  name                     = "dib00016githubactions"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2" # requires minimum of TLS1_2

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "sac" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# Outputs - These will be the values that we need to use in the app infrastructure configuration's backend block.

output "resource-group" {
  description = "Resource group name"
  value       = azurerm_resource_group.rg.name
}

output "storage-account" {
  description = "Storage account name"
  value       = azurerm_storage_account.sa.name
}

output "container" {
  description = "Container name of storage account"
  value       = azurerm_storage_container.sac.name
}
# primary access key (which will be added to the GitHub secrets).
output "arm_access_key" {
  description = "Primary access key"
  sensitive   = true
  value       = azurerm_storage_account.sa.primary_access_key
}