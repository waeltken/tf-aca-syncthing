locals {
  suffix = random_bytes.unique.hex
}

resource "random_bytes" "unique" {
  length = 2
}

resource "azurerm_resource_group" "default" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "default" {
  name                = "syncthing-vnet"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  address_space       = ["10.0.0.0/16"]
}
resource "azurerm_subnet" "syncthing" {
  name                 = "syncthing-subnet"
  resource_group_name  = azurerm_virtual_network.default.resource_group_name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.0.0/23"]
}

resource "azurerm_network_security_group" "inbound_aks" {
  name                = "inbound-aks-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_log_analytics_workspace" "default" {
  name                = "syncthing-log-analytics"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

resource "azurerm_container_app_environment" "default" {
  name                     = "syncthing-aca-env"
  location                 = azurerm_resource_group.default.location
  resource_group_name      = azurerm_resource_group.default.name
  infrastructure_subnet_id = azurerm_subnet.syncthing.id

  log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id
}

resource "azurerm_storage_account" "default" {
  name                            = "syncthingstorage${local.suffix}"
  location                        = azurerm_resource_group.default.location
  resource_group_name             = azurerm_resource_group.default.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_share" "data" {
  name                 = "syncthing-data"
  storage_account_name = azurerm_storage_account.default.name
  quota                = 1024
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "syncthing-data"
  container_app_environment_id = azurerm_container_app_environment.default.id
  account_name                 = azurerm_storage_account.default.name
  share_name                   = azurerm_storage_share.data.name
  access_key                   = azurerm_storage_account.default.primary_access_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app" "default" {
  name                         = "syncthing-app"
  container_app_environment_id = azurerm_container_app_environment.default.id
  resource_group_name          = azurerm_resource_group.default.name
  revision_mode                = "Single"

  template {
    container {
      name   = "syncthing"
      image  = "syncthing/syncthing:latest"
      cpu    = 2
      memory = "4Gi"

      volume_mounts {
        name = "syncthing-data"
        path = "/var/syncthing"
      }
    }

    volume {
      name         = azurerm_container_app_environment_storage.data.name
      storage_name = azurerm_storage_share.data.name
      storage_type = "AzureFile"
    }
  }
  # Allow public ingress traffic
  ingress {
    external_enabled = true
    target_port      = 8384

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  lifecycle {
    ignore_changes = [ingress.0.custom_domain]
  }
}

output "default_domain_name" {
  value = azurerm_container_app.default.latest_revision_fqdn
}

