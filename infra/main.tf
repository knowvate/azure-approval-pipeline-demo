data "azurerm_resource_group" "env" {
  name = var.resource_group_name
}

locals {
  tags = {
    Environment = var.environment
    Owner       = var.owner_tag
    Workload    = "approval-pipeline-demo"
    ManagedBy   = "terraform"
    Stack       = "infra"
    Repository  = "knowvate/azure-approval-pipeline-demo"
    CostCenter  = "personal-lab"
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# F1 (Free) keeps the demo at £0. A real Production would use at least B1/S1
# with always_on, and P1v3+ for zone redundancy.
resource "azurerm_service_plan" "app" {
  name                = "asp-approvaldemo-${var.environment_key}"
  resource_group_name = data.azurerm_resource_group.env.name
  location            = data.azurerm_resource_group.env.location
  os_type             = "Linux"
  sku_name            = "F1"
  tags                = local.tags

  #checkov:skip=CKV_AZURE_211:Free tier on purpose - demo cost is £0.
  #checkov:skip=CKV_AZURE_212:Zone redundancy needs Premium; not for a demo.
  #checkov:skip=CKV_AZURE_225:Zone redundancy needs Premium; not for a demo.
}

resource "azurerm_linux_web_app" "app" {
  name                = "app-approvaldemo-${var.environment_key}-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.env.name
  location            = data.azurerm_resource_group.env.location
  service_plan_id     = azurerm_service_plan.app.id
  https_only          = true

  # Deploys authenticate with Entra ID (the pipeline's OIDC identity), so
  # the legacy username/password publishing endpoints stay off.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = false # not available on F1
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"
    app_command_line    = "node src/server.js"
    health_check_path   = "/healthz"

    health_check_eviction_time_in_min = 10

    application_stack {
      node_version = "22-lts"
    }
  }

  app_settings = {
    APP_ENVIRONMENT                = var.environment
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false" # the artifact is already built
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags

  #checkov:skip=CKV_AZURE_214:always_on is not available on the F1 (Free) tier.
  #checkov:skip=CKV_AZURE_13:Public demo page - no sign-in by design.
  #checkov:skip=CKV_AZURE_17:Client certificates would block a public demo page.
  #checkov:skip=CKV_AZURE_88:No persistent storage needed; the app is stateless.
  #checkov:skip=CKV_AZURE_222:Public network access is the point of a public demo page.
}
