resource "azurerm_service_plan" "temp" {
  name                = var.ServicePlanFEName
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  os_type  = "Windows"
  sku_name = "B1"
}

resource "azurerm_windows_web_app" "this" {
  name                = var.WebAppName
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.temp.id

  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }

  site_config {
    ftps_state                  = "Disabled"
    minimum_tls_version         = "1.2"
    vnet_route_all_enabled      = true
    scm_use_main_ip_restriction = true
  }
}

data "archive_file" "frontend_app_code" {
  type        = "zip"
  source_dir  = "FrontendCode"
  output_path = "Temp/frontendcode.zip"
  excludes    = ["build", "node_modules", ".env", ".env.development"]
}

resource "null_resource" "frontend_publish" {
  provisioner "local-exec" {
    command = <<-EOT
    cd FrontendCode
    New-Item -Path .env -force
    Add-Content -Path .env -Value "REACT_APP_redirectUri=https://${azurerm_windows_web_app.this.default_hostname}"
    Add-Content -Path .env -Value "REACT_APP_clientID=${azuread_application.frontendapp.application_id}"
    Add-Content -Path .env -Value "REACT_APP_TenantID=${var.AzureADTenantID}"
    Add-Content -Path .env -Value "REACT_APP_SandboxSubscription=${var.SandboxSubID}"
    Add-Content -Path .env -Value "REACT_APP_APIMName=${azurerm_api_management.this.gateway_url}"
    Add-Content -Path .env -Value "REACT_APP_APIName=${azurerm_api_management_api.this.name}"
    Add-Content -Path .env -Value "REACT_APP_APICreate=${azurerm_api_management_api_operation.create.url_template}"
    Add-Content -Path .env -Value "REACT_APP_APIList=${azurerm_api_management_api_operation.list.url_template}"
    Add-Content -Path .env -Value "REACT_APP_APIDelete=${azurerm_api_management_api_operation.delete.url_template}"
    Add-Content -Path .env -Value "REACT_APP_APIReset=${azurerm_api_management_api_operation.reset.url_template}"

    npm install
    npm run build
    Compress-Archive -Path build\* -DestinationPath ..\Temp\frontendbuild.zip -force
    az webapp deployment source config-zip --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_windows_web_app.this.name} --src ..\Temp\frontendbuild.zip --only-show-errors > ..\Temp\frontendoutput.txt
    EOT

    interpreter = ["PowerShell", "-Command"]
  }
  triggers = {
    input_json     = filemd5(data.archive_file.frontend_app_code.output_path)
    deploy_target  = azurerm_windows_web_app.this.id
    webapphostname = azurerm_windows_web_app.this.default_hostname
    clientid       = azuread_application.frontendapp.application_id
    APIMName       = var.APIMName
    tenantid       = var.AzureADTenantID
    sandboxsubid   = var.SandboxSubID
    APIName        = azurerm_api_management_api.this.name
    createurl      = azurerm_api_management_api_operation.create.url_template
    listurl        = azurerm_api_management_api_operation.list.url_template
    deleteurl      = azurerm_api_management_api_operation.delete.url_template
    reseturl       = azurerm_api_management_api_operation.reset.url_template
  }
}
