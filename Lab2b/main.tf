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

#
# Current Azure Client
#

data "azurerm_client_config" "current" {}

#
# Resource Group
#

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg2"
  location = "East US"

  tags = {
    "Cost Center" = "000"
  }
}

#
# Task 2 Policy (commented intentionally)
#
# In real Terraform workflows we do not create
# temporary policies only to immediately replace them.
# Therefore this task is documented but skipped in execution.
#

data "azurerm_policy_definition" "require_tag" {
  display_name = "Require a tag and its value on resources"
}

resource "azurerm_resource_group_policy_assignment" "task2_require_tag" {
  name                 = "require-cost-center"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.require_tag.id

  description = "Require Cost Center tag and its value on all resources"

  parameters = <<PARAMETERS
{
  "tagName": {
    "value": "Cost Center"
  },
  "tagValue": {
    "value": "000"
  }
}
PARAMETERS
}

#
# Task 3 - Inherit Tag Policy
#

data "azurerm_policy_definition" "inherit_tag" {
  display_name = "Inherit a tag from the resource group if missing"
}

resource "azurerm_resource_group_policy_assignment" "inherit_tag_assignment" {
  name                 = "inherit-cost-center-tag"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = data.azurerm_policy_definition.inherit_tag.id

  description = "Inherit the Cost Center tag and its value 000 from the resource group if missing"

  location = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  parameters = <<PARAMETERS
{
  "tagName": {
    "value": "Cost Center"
  }
}
PARAMETERS
}

#
# Required permissions for remediation
#

resource "azurerm_role_assignment" "policy_tag_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Tag Contributor"

  principal_id = azurerm_resource_group_policy_assignment.inherit_tag_assignment.identity[0].principal_id
}

#
# Policy Remediation
#

resource "azurerm_resource_group_policy_remediation" "remediate_tags" {
  name                 = "remediate-cost-center-tags"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_assignment_id = azurerm_resource_group_policy_assignment.inherit_tag_assignment.id

  depends_on = [
    azurerm_role_assignment.policy_tag_contributor
  ]
}

#
# Resource Lock
#

resource "azurerm_management_lock" "rg_lock" {
  name       = "rg-lock"
  scope      = azurerm_resource_group.rg.id
  lock_level = "CanNotDelete"

  notes = "Lab 02b Resource Lock - Prevent Deletion"

  depends_on = [
    azurerm_resource_group_policy_assignment.inherit_tag_assignment,
    azurerm_resource_group_policy_remediation.remediate_tags
  ]
}

#
# Random suffix for globally unique storage account
#

resource "random_string" "sa_suffix" {
  length  = 8
  special = false
  upper   = false
}

#
# Storage Account for policy testing
#

resource "azurerm_storage_account" "test_sa" {
  name                     = "az104demo${random_string.sa_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  depends_on = [
    azurerm_resource_group_policy_assignment.inherit_tag_assignment
  ]
}