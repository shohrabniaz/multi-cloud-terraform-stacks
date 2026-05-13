################################################################################
# Azure App Service with Key Vault references
#
# Why this pattern: App Service is the right answer for many small web apps
# in Azure — managed certs, slot deployments, scale rules, no container
# orchestration overhead. Key Vault references mean secrets never touch the
# app settings JSON, even on diff/export.
################################################################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "name"     { type = string }
variable "location" { type = string, default = "australiaeast" }

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
}

################################################################################
# Key Vault — note RBAC mode (not access-policy mode), purge protection ON
################################################################################

resource "azurerm_key_vault" "this" {
  name                       = "${var.name}-kv"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "DATABASE-PASSWORD"
  value        = "REPLACE-ME"   # actually populated out-of-band by Ops
  key_vault_id = azurerm_key_vault.this.id

  lifecycle {
    ignore_changes = [value]
  }
}

################################################################################
# App Service plan + Linux web app with system-assigned identity
################################################################################

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  os_type             = "Linux"
  sku_name            = "P1v3"
  worker_count        = 2
  zone_balancing_enabled = true
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true

  identity { type = "SystemAssigned" }

  site_config {
    always_on              = true
    ftps_state             = "Disabled"
    http2_enabled          = true
    minimum_tls_version    = "1.2"
    use_32_bit_worker      = false
    health_check_path      = "/healthz/ready"
    health_check_eviction_time_in_min = 5

    application_stack {
      docker_image_name        = "example/webapp:1.0.0"
      docker_registry_url      = "https://ghcr.io"
    }
  }

  # NOTE: secret is referenced from Key Vault, not stored here.
  app_settings = {
    "DATABASE_PASSWORD"     = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.this.name};SecretName=${azurerm_key_vault_secret.db_password.name})"
    "WEBSITES_PORT"         = "8080"
    "DOCKER_ENABLE_CI"      = "true"
  }
}

# Grant the App Service identity Key Vault Secrets User on the vault.
resource "azurerm_role_assignment" "app_kv_reader" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

################################################################################
# Diagnostic settings — push platform logs to a workspace
################################################################################

variable "log_analytics_workspace_id" {
  description = "Workspace to send diagnostic logs to. Required."
  type        = string
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "to-workspace"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }

  metric { category = "AllMetrics" }
}

output "app_url" {
  value = "https://${azurerm_linux_web_app.this.default_hostname}"
}
