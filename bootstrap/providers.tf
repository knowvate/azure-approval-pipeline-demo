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

  # Bootstrap creates the state storage, so its own state stays local (and
  # out of git - see .gitignore). Applied once by a person, never by the
  # pipeline.
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # The state account has shared keys turned off, so data-plane calls must
  # use Entra ID.
  storage_use_azuread = true
}
