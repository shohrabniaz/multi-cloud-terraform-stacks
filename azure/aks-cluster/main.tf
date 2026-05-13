################################################################################
# Minimal AKS example consuming the aks-terraform-module
#
# For the full module source see:
# https://github.com/shohrabniaz/aks-terraform-module
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
variable "vnet_subnet_id" { type = string }
variable "aad_admin_group_object_id" { type = string }

module "aks" {
  source = "git::https://github.com/shohrabniaz/aks-terraform-module.git//?ref=main"

  name                = var.name
  location            = var.location
  resource_group_name = "${var.name}-rg"

  vnet_subnet_id                  = var.vnet_subnet_id
  azure_ad_admin_group_object_ids = [var.aad_admin_group_object_id]

  user_node_pools = {
    apps = {
      vm_size   = "Standard_D4s_v5"
      min_count = 2
      max_count = 10
    }
  }

  tags = {
    environment = "demo"
    project     = "multi-cloud-examples"
  }
}

output "cluster_name" {
  value = module.aks.cluster_name
}
