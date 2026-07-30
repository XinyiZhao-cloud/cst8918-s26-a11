resource "azurerm_resource_group" "rg" {
  name     = "dib00016-a12-rg"
  location = "Canada Central"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "dib00016-a12-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "dib00016-a12-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}