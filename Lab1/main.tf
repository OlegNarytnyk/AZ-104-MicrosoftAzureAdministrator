terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {}

data "azuread_client_config" "current" {}

data "azuread_domains" "default" {
  only_initial = true
}

resource "azuread_user" "lab_user" {
  user_principal_name = "az104-user1@${data.azuread_domains.default.domains[0].domain_name}"

  display_name = "az104-user1"
  password     = "TempPassword123!"

  force_password_change = true

  job_title      = "IT Lab Administrator"
  department     = "IT"
  usage_location = "US"

  account_enabled = true
}

resource "azuread_invitation" "guest_user" {
  user_email_address = "narytnyk.supp@gmail.com"
  redirect_url       = "https://portal.azure.com"

  message {
    body = "Welcome to Azure and our group project"
  }
}

resource "azuread_group" "lab_group" {
  display_name     = "IT Lab Administrators"
  description      = "Administrators that manage the IT lab"
  security_enabled = true

  owners = [
    data.azuread_client_config.current.object_id
  ]
}

resource "azuread_group_member" "user_member" {
  group_object_id  = azuread_group.lab_group.object_id
  member_object_id = azuread_user.lab_user.object_id
}

resource "azuread_group_member" "guest_member" {
  group_object_id  = azuread_group.lab_group.object_id
  member_object_id = azuread_invitation.guest_user.user_id
}