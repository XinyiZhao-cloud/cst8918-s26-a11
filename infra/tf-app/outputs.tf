output "resource_group_name" {
  description = "Name of the app infrastructure resource group"
  value       = azurerm_resource_group.rg.name
}
