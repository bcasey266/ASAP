data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.region
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.managed_identity_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_role_assignment" "sandbox_subscription_owner" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = "/subscriptions/${var.sandbox_azure_subscription_id}"
  role_definition_name = "Owner"
}

resource "azuread_directory_role_assignment" "aad_user_read" {
  principal_object_id = azurerm_user_assigned_identity.this.principal_id
  role_id             = "88d8e3e3-8f55-4a1e-953a-9b9898b8876b"
}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  tenant_id                  = var.azuread_tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  sku_name                   = "standard"
  enable_rbac_authorization  = true

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = tolist(var.ip_allowlist[*].ip)
  }
}

resource "azurerm_role_assignment" "akv_secret_user" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
}

resource "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  account_replication_type        = "LRS"
  account_tier                    = "Standard"
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Deny"
    ip_rules       = tolist(var.ip_allowlist[*].ip)
    bypass         = ["Logging", "Metrics", "AzureServices"]

    private_link_access {
      endpoint_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.this.name}/providers/Microsoft.Logic/workflows/*"
      endpoint_tenant_id   = var.azuread_tenant_id
    }
  }
}

resource "azurerm_role_assignment" "storage_account_contributor" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Contributor"
}

resource "azurerm_role_assignment" "blob_data_owner" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Owner"
}

resource "azurerm_role_assignment" "table_data_contributor" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Table Data Contributor"
}

resource "azurerm_role_assignment" "queue_data_contributor" {
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Queue Data Contributor"
}

resource "azurerm_key_vault_secret" "storage_account_connection_string" {
  name         = "${var.azurerm_storage_account.this.name}-connection-string"
  key_vault_id = azurerm_key_vault.this.id
  value        = azurerm_storage_account.this.primary_connection_string
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  sku               = "PerGB2018"
  retention_in_days = 30
}

resource "azurerm_application_insights" "this" {
  name                = var.application_insights_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  application_type = "web"
  workspace_id     = azurerm_log_analytics_workspace.this.id
}

module "Networking" {
  count  = var.enable_private_networking == true ? 1 : 0
  source = "./Modules/Networking"

  vnet_name           = var.vnet_name
  region              = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  vnet_ip_space = var.vnet_ip_space

  storage_account_name = azurerm_storage_account.this.name
  storage_account_id   = azurerm_storage_account.this.id

  key_vault_name = azurerm_key_vault.this.name
  key_vault_id   = azurerm_key_vault.this.id
}


module "FunctionApp" {
  source = "./Modules/FunctionApp"

  depends_on = [
    module.Networking,
    azurerm_role_assignment.akv_secret_user,
    azurerm_role_assignment.storage_account_contributor,
    azurerm_role_assignment.blob_data_owner,
    azurerm_role_assignment.table_data_contributor,
    azurerm_role_assignment.queue_data_contributor
  ]

  app_service_plan_name = var.app_service_plan_name
  function_app_name     = var.function_app_name
  region                = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name

  storage_account_name              = azurerm_storage_account.this.name
  storage_account_connection_string = azurerm_key_vault_secret.storage_account_connection_string.versionless_id
  queue_notifications               = module.Notifications.queue_notifications

  subnet_integration_id = var.enable_private_networking == true ? module.Networking[0].subnet_integration_ids : null
  ip_allowlist          = var.ip_allowlist

  user_identity_id        = azurerm_user_assigned_identity.this.id
  user_identity_client_id = azurerm_user_assigned_identity.this.client_id

  app_insights_id                  = azurerm_application_insights.this.id
  app_insights_connection_string   = azurerm_application_insights.this.connection_string
  app_insights_instrumentation_key = azurerm_application_insights.this.instrumentation_key

  platform_subscription_id      = data.azurerm_client_config.current.subscription_id
  sandbox_azure_subscription_id = var.sandbox_azure_subscription_id
  frontend_url                  = module.Frontend.FrontendPortalURL
}

module "Notifications" {
  source = "./Modules/Notifications"

  logic_app_name      = var.logic_app_name
  logic_app_region    = var.logic_app_region
  resource_group_name = azurerm_resource_group.this.name

  resource_group_id = azurerm_resource_group.this.id

  storage_account_name = azurerm_storage_account.this.name
  storage_account_id   = azurerm_storage_account.this.id

  azuread_tenant_id             = var.azuread_tenant_id
  platform_subscription_id      = data.azurerm_client_config.current.subscription_id
  sandbox_azure_subscription_id = var.sandbox_azure_subscription_id
  frontend_url                  = module.Frontend.FrontendPortalURL

}

module "APIM" {
  source = "./Modules/APIM"

  frontend_app_registration_name = var.frontend_app_registration_name
  FrontendHostname               = module.Frontend.FrontendHostname
  region                         = var.logic_app_region
  resource_group_name            = azurerm_resource_group.this.name
  api_management_name            = var.api_management_name
  api_management_admin_name      = var.api_management_admin_name
  api_management_admin_email     = var.api_management_admin_email
  function_app_name              = var.function_app_name
  FunctionAppHostName            = module.FunctionApp.FunctionAppHostName
  FunctionAppHostKey             = module.FunctionApp.FunctionAppHostKey
  azuread_tenant_id              = var.azuread_tenant_id
}

module "Frontend" {
  source = "./Modules/Frontend"

  region                         = var.logic_app_region
  resource_group_name            = azurerm_resource_group.this.name
  app_service_plan_frontend_name = var.app_service_plan_frontend_name
  web_app_frontend_name          = var.web_app_frontend_name
  FrontendAppID                  = module.APIM.FrontendAppID
  azuread_tenant_id              = var.azuread_tenant_id
  sandbox_azure_subscription_id  = var.sandbox_azure_subscription_id
  APIMGatewayURL                 = module.APIM.APIMGatewayURL
  APIName                        = module.APIM.APIName
  APICreateURL                   = module.APIM.APICreateURL
  APIListURL                     = module.APIM.APIListURL
  APIDeleteURL                   = module.APIM.APIDeleteURL
  APIResetURL                    = module.APIM.APIResetURL
}
