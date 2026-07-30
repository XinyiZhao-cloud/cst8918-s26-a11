# file to define the terraform and provider blocks while pointing to remote tfstate file using our service principal (robot/system identity) and federated credentials ()
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0"
    }
  }
  backend "azurerm" { # where terraform remote state lives
    resource_group_name  = "dib00016-githubactions-rg"
    storage_account_name = "dib00016githubactions"
    container_name       = "tfstate"
    key                  = "prod.app.tfstate"
    use_oidc             = true # local plans will scream about this line looking for a token; for local `terraform plan` runs just to test output comment this out
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
  use_oidc = true # same as above - for local `terraform plan` runs for testing comment this out
}