terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partially configured: the pipeline passes storage account and container
  # per environment with -backend-config, so each environment has its own
  # state that only its own identities can write.
  backend "azurerm" {
    key              = "infra.tfstate"
    use_azuread_auth = true
    use_oidc         = true
  }
}

provider "azurerm" {
  features {}
  # Identities are scoped to one resource group, so they cannot register
  # resource providers at subscription level.
  resource_provider_registrations = "none"
}
