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
  primary_location   = "canadacentral"
  secondary_location = "canadaeast"

  admin_username = "localadmin"
  admin_password = "Password12345!"
  vm_size        = "Standard_B1ms"
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "region1" {
  name     = "az104-rg-region1"
  location = local.primary_location
}

resource "azurerm_resource_group" "region2" {
  name     = "az104-rg-region2"
  location = local.secondary_location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "az104-10-vnet"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.region1.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "az104-10-vm0-nic"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "az104-10-vm0"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name
  size                = local.vm_size

  admin_username = local.admin_username
  admin_password = local.admin_password

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }
}

resource "azurerm_recovery_services_vault" "rsv_region1" {
  name                = "az104-rsv-region1"
  location            = azurerm_resource_group.region1.location
  resource_group_name = azurerm_resource_group.region1.name

  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
  soft_delete_enabled = true
}

resource "azurerm_backup_policy_vm" "backup_policy" {
  name                = "az104-backup"
  resource_group_name = azurerm_resource_group.region1.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_region1.name

  timezone = "Central Standard Time"

  backup {
    frequency = "Daily"
    time      = "00:00"
  }

  instant_restore_retention_days = 2

  retention_daily {
    count = 30
  }
}

resource "azurerm_backup_protected_vm" "protected_vm" {
  resource_group_name = azurerm_resource_group.region1.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv_region1.name

  source_vm_id     = azurerm_windows_virtual_machine.vm.id
  backup_policy_id = azurerm_backup_policy_vm.backup_policy.id

  depends_on = [
    azurerm_windows_virtual_machine.vm
  ]
}

resource "azurerm_storage_account" "diagnostics" {
  name                     = "az104diag${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.region1.name
  location                 = azurerm_resource_group.region1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_monitor_diagnostic_setting" "rsv_diagnostics" {
  name               = "Logs and Metrics to storage"
  target_resource_id = azurerm_recovery_services_vault.rsv_region1.id
  storage_account_id = azurerm_storage_account.diagnostics.id

  enabled_log {
    category = "AzureBackupReport"
  }

  enabled_log {
    category = "AddonAzureBackupJobs"
  }

  enabled_log {
    category = "AddonAzureBackupAlerts"
  }

  enabled_log {
    category = "AzureSiteRecoveryJobs"
  }

  enabled_log {
    category = "AzureSiteRecoveryEvents"
  }

  metric {
    category = "Health"
    enabled  = true
  }
}

resource "azurerm_recovery_services_vault" "rsv_region2" {
  name                = "az104-rsv-region2"
  location            = azurerm_resource_group.region2.location
  resource_group_name = azurerm_resource_group.region2.name

  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
  soft_delete_enabled = true
}