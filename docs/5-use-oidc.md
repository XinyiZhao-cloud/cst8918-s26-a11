CST8918 - DevOps: Infrastructure as Code  
Prof. Robert McKenney

# Lab 12: Terraform CI/CD on Azure with GitHub Actions

## 5. Use OpenID Connect (OIDC) in Terraform Configuration

OpenID Connect (OIDC) is a simple identity layer on top of the OAuth 2.0 protocol. It allows clients to verify the identity of the end-user based on the authentication performed by an authorization server, as well as to obtain basic profile information about the end-user in an interoperable and REST-like manner.

OIDC is used in this lab to authenticate with Azure resources. This means that your Terraform configuration will authenticate directly to Azure, and that there is no need to store credentials as long-lived secrets which provides security benefits.

### Update the Terraform configuration
Update the `terraform.tf` file in the `infra/tf-app` folder. 

Add the `use_oidc = true` argument to both the `backend` and  `azurerm` provider blocks.

See lines 13 and 19 below:

```hcl
terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.96.0"
    }
  }
  backend "azurerm" {
    storage_account_name = "mckennrgithubactions"
    container_name       = "tfstate"
    key                  = "prod.app.tfstate"
    use_oidc             = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

```
