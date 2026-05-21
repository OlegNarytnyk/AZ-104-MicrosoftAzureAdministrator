terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  location = "canadacentral"
}

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg7"
  location = local.location
}

resource "random_string" "storage_suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.70.0.0/16"]
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.70.0.0/24"]

  service_endpoints = [
    "Microsoft.Storage"
  ]
}

resource "azurerm_storage_account" "storage" {
  name                     = "az104st${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "RAGRS"

  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.default.id]
    bypass                     = ["AzureServices"]
  }

  depends_on = [
    azurerm_subnet.default
  ]
}

resource "azurerm_storage_management_policy" "lifecycle_policy" {
  storage_account_id = azurerm_storage_account.storage.id

  rule {
    name    = "Movetocool"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }
}

resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container_immutability_policy" "data_retention" {
  storage_container_resource_manager_id = azurerm_storage_container.data.resource_manager_id

  immutability_period_in_days = 180
  protected_append_writes     = false
}

resource "azurerm_storage_blob" "sample_blob" {
  name                   = "securitytest/sample.txt"
  storage_account_name   = azurerm_storage_account.storage.name
  storage_container_name = azurerm_storage_container.data.name
  type                   = "Block"
  source_content         = "This is a sample file uploaded by Terraform for AZ-104 Lab 07."
  access_tier            = "Hot"

  depends_on = [
    azurerm_storage_container_immutability_policy.data_retention
  ]
}

resource "azurerm_storage_share" "share1" {
  name                 = "share1"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 5
  access_tier          = "TransactionOptimized"
}

resource "azurerm_storage_share_directory" "sample_directory" {
  name                 = "securitytest"
  share_name           = azurerm_storage_share.share1.name
  storage_account_name = azurerm_storage_account.storage.name
}

resource "azurerm_storage_share_file" "sample_file" {
  name             = "sample.txt"
  storage_share_id = azurerm_storage_share.share1.id
  path             = azurerm_storage_share_directory.sample_directory.name
  source           = "sample.txt"

  depends_on = [
    azurerm_storage_share_directory.sample_directory
  ]
}