# One subscription, three environments. Tags say which environment a
# resource belongs to, but tags are only labels: anyone with Contributor on
# the subscription can change or ignore them. The real boundaries are:
#
#   1. One resource group per environment.
#   2. Two identities per environment, with roles on THAT resource group only:
#        plan   - read-only (custom role), trusted for the main branch, so
#                 plans need no approval and can never change anything.
#        deploy - Contributor, trusted ONLY for the matching GitHub
#                 environment, which is where the approval gates live.
#   3. One state container per environment, writable only by that
#      environment's identities.
#
# So the Development pipeline physically cannot touch Production, and
# nothing can change Production until someone approves the production
# environment in GitHub.

locals {
  environments = {
    development = { key = "dev", label = "Development" }
    uat         = { key = "uat", label = "UAT" }
    production  = { key = "prod", label = "Production" }
  }

  common_tags = {
    Owner      = var.owner_tag
    Workload   = "approval-pipeline-demo"
    ManagedBy  = "terraform"
    Stack      = "bootstrap"
    Repository = "knowvate/azure-approval-pipeline-demo"
    CostCenter = "personal-lab"
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ---------------------------------------------------------------- shared --
# Identities and state live here, outside the environment resource groups:
# a deploy identity with Contributor on its environment's group must not be
# able to delete or re-point itself, or another environment's state.
resource "azurerm_resource_group" "shared" {
  name     = "rg-approvaldemo-shared"
  location = var.location
  tags     = merge(local.common_tags, { Environment = "Shared" })
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "stapprovaldemo${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.shared.name
  location                        = azurerm_resource_group.shared.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(local.common_tags, { Environment = "Shared", Component = "terraform-state" })

  #checkov:skip=CKV_AZURE_33:Queue logging - no queues are used, this account only holds Terraform state.
  #checkov:skip=CKV_AZURE_59:Public network access stays on so GitHub-hosted runners can reach state; access needs Entra ID (shared keys are off).
  #checkov:skip=CKV_AZURE_206:LRS is enough for a demo; versioning plus soft delete cover accidental state loss.
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys are out of scope for the demo; Microsoft-managed encryption is on.
  #checkov:skip=CKV2_AZURE_33:No private endpoint - GitHub-hosted runners are outside any VNet.
  #checkov:skip=CKV2_AZURE_40:Shared key access is already disabled (shared_access_key_enabled = false); the check misreads it.
  #checkov:skip=CKV2_AZURE_41:No SAS tokens are issued - shared keys are off, so SAS cannot be used.
}

resource "azurerm_storage_container" "tfstate" {
  for_each              = local.environments
  name                  = "tfstate-${each.key}"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"

  #checkov:skip=CKV2_AZURE_21:Blob read logging needs a Log Analytics workspace; state access is Entra ID-only and visible in the Activity Log.
}

# ---------------------------------------------------------- environments --
resource "azurerm_resource_group" "env" {
  for_each = local.environments
  name     = "rg-approvaldemo-${each.value.key}"
  location = var.location
  tags     = merge(local.common_tags, { Environment = each.value.label })
}

# Read-only role for plans. Reader alone is not enough: Terraform's App
# Service provider reads app settings through a POST "list" call, which
# Reader excludes. Nothing here can create, change or delete.
resource "azurerm_role_definition" "planner" {
  name        = "approvaldemo-terraform-planner"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Read everything Terraform needs to plan the approval demo; no write actions."

  permissions {
    actions = [
      "*/read",
      "Microsoft.Web/sites/config/list/action",
    ]
  }

  assignable_scopes = [for rg in azurerm_resource_group.env : rg.id]
}

resource "azurerm_user_assigned_identity" "plan" {
  for_each            = local.environments
  name                = "id-approvaldemo-${each.value.key}-plan"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = merge(local.common_tags, { Environment = each.value.label, Component = "pipeline-identity" })
}

resource "azurerm_user_assigned_identity" "deploy" {
  for_each            = local.environments
  name                = "id-approvaldemo-${each.value.key}-deploy"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = merge(local.common_tags, { Environment = each.value.label, Component = "pipeline-identity" })
}

# Plan identities trust any job on main that names NO environment. Read-only,
# so it is safe for them to run before anyone approves anything. Pull
# requests get a different subject (…:pull_request) and cannot log in at all.
resource "azurerm_federated_identity_credential" "plan" {
  for_each                  = local.environments
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.plan[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${var.github_oidc_subject_prefix}:ref:refs/heads/main"
}

# Deploy identities trust ONLY a job running in the matching GitHub
# environment. A job can only enter "production" after its required
# reviewers approve, and only from main (deployment branch policy), so this
# credential is the approval gate as far as Azure is concerned.
resource "azurerm_federated_identity_credential" "deploy" {
  for_each                  = local.environments
  name                      = "github-environment-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${var.github_oidc_subject_prefix}:environment:${each.key}"
}

resource "azurerm_role_assignment" "plan_reader" {
  for_each           = local.environments
  scope              = azurerm_resource_group.env[each.key].id
  role_definition_id = azurerm_role_definition.planner.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.plan[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deploy_contributor" {
  for_each             = local.environments
  scope                = azurerm_resource_group.env[each.key].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# State: each environment's identities can write (plans take a lock) only
# their own container; Reader on the account lets the azurerm backend find it.
resource "azurerm_role_assignment" "state_blob" {
  for_each = merge(
    { for k, v in local.environments : "${k}-plan" => { env = k, principal = azurerm_user_assigned_identity.plan[k].principal_id } },
    { for k, v in local.environments : "${k}-deploy" => { env = k, principal = azurerm_user_assigned_identity.deploy[k].principal_id } },
  )
  scope                = azurerm_storage_container.tfstate[each.value.env].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state_account_reader" {
  for_each = merge(
    { for k, v in local.environments : "${k}-plan" => azurerm_user_assigned_identity.plan[k].principal_id },
    { for k, v in local.environments : "${k}-deploy" => azurerm_user_assigned_identity.deploy[k].principal_id },
  )
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Reader"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}
