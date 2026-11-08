# Everything the pipeline needs, none of it secret: OIDC needs no stored
# credentials, only these IDs (set as GitHub variables, not secrets).
output "tenant_id" {
  value = azurerm_user_assigned_identity.deploy["development"].tenant_id
}

output "tfstate_resource_group" {
  value = azurerm_resource_group.shared.name
}

output "tfstate_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "environments" {
  value = {
    for k, v in local.environments : k => {
      resource_group   = azurerm_resource_group.env[k].name
      plan_client_id   = azurerm_user_assigned_identity.plan[k].client_id
      deploy_client_id = azurerm_user_assigned_identity.deploy[k].client_id
      state_container  = azurerm_storage_container.tfstate[k].name
    }
  }
}
