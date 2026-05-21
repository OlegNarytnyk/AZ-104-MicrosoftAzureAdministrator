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

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "az104-rg9"
  location = local.location
}

resource "azurerm_container_group" "aci" {
  name                = "az104-c1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  os_type         = "Linux"
  ip_address_type = "Public"
  dns_name_label  = "az104-c1-${random_string.suffix.result}"

  container {
    name   = "az104-c1"
    image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
    cpu    = "1"
    memory = "1"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  exposed_port {
    port     = 80
    protocol = "TCP"
  }

  restart_policy = "Always"
}