terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

provider "azuread" {}

data "azurerm_client_config" "current" {}

#
# Management Group
#

resource "azurerm_management_group" "lab_mg" {
  display_name               = "az104-mg1"
  name                       = "az104-mg1"
  parent_management_group_id = data.azurerm_client_config.current.tenant_id
}

#
# Helpdesk Group
#

resource "azuread_group" "helpdesk" {
  display_name     = "helpdesk"
  security_enabled = true
}

#
# Built-in Role Assignment
#

data "azurerm_role_definition" "vm_contributor" {
  name = "Virtual Machine Contributor"
}

resource "azurerm_role_assignment" "vm_contributor_assignment" {
  scope              = azurerm_management_group.lab_mg.id
  role_definition_id = data.azurerm_role_definition.vm_contributor.role_definition_id
  principal_id       = azuread_group.helpdesk.object_id
}

#
# Custom Role
#

resource "azurerm_role_definition" "custom_support_request" {
  name        = "Custom Support Request"
  scope       = azurerm_management_group.lab_mg.id
  description = "A custom contributor role for support requests."

  permissions {
    actions = [
      "Microsoft.Support/*"
    ]

    not_actions = [
      "Microsoft.Support/register/action"
    ]
  }

  assignable_scopes = [
    azurerm_management_group.lab_mg.id
  ]
}

#
# Assign Custom Role
#

resource "azurerm_role_assignment" "custom_role_assignment" {
  scope              = azurerm_management_group.lab_mg.id
  role_definition_id = azurerm_role_definition.custom_support_request.role_definition_resource_id
  principal_id       = azuread_group.helpdesk.object_id
}