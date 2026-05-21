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
  location       = "canadacentral"
  admin_username = "localadmin"
  admin_password = "Password12345!"
  vm_size        = "Standard_B1ms"
  email_address  = "oleg.naritnik@gmail.com"
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg11"
  location = local.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "az104-11-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.11.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.11.0.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "az104-vm0-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "az104-vm0"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
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

resource "azurerm_log_analytics_workspace" "law" {
  name                = "az104-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "az104-vm-insights-dcr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "logAnalyticsDestination"
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["logAnalyticsDestination"]
  }

  data_sources {
    performance_counter {
      name                          = "performanceCounters"
      streams                       = ["Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes"
      ]
    }
  }
}

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule_association" "vm_dcr_association" {
  name                    = "az104-vm0-dcr-association"
  target_resource_id      = azurerm_windows_virtual_machine.vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id

  depends_on = [
    azurerm_virtual_machine_extension.azure_monitor_agent
  ]
}

resource "azurerm_monitor_action_group" "operations_team" {
  name                = "Alert the operations team"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "AlertOps"

  email_receiver {
    name          = "VM was deleted"
    email_address = local.email_address
  }
}

resource "azurerm_monitor_activity_log_alert" "vm_deleted_alert" {
  name                = "VM was deleted"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "A VM in your resource group was deleted"

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.operations_team.id
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_monitor_alert_processing_rule_suppression" "planned_maintenance" {
  name                = "Planned Maintenance"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = ["/subscriptions/${data.azurerm_client_config.current.subscription_id}"]
  description         = "Suppress notifications during planned maintenance."

  condition {
    alert_rule_name {
      operator = "Equals"
      values   = [azurerm_monitor_activity_log_alert.vm_deleted_alert.name]
    }
  }

  schedule {
    effective_from  = "2026-05-21T22:00:00"
    effective_until = "2026-05-22T07:00:00"
    time_zone       = "Central Standard Time"
  }
}