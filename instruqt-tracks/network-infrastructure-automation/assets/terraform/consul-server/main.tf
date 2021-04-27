provider "azurerm" {
  version = "=2.0.0"
  features {}
}

data "terraform_remote_state" "vnet" {
  backend = "local"

  config = {
    path = "../vnet/terraform.tfstate"
  }
}


resource "azurerm_public_ip" "consul" {
  name                = "consul-ip"
  location            = data.terraform_remote_state.vnet.outputs.resource_group_location
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create network interface
resource "azurerm_network_interface" "consulserver-nic" {
    name                      = "consulserverNIC"
    location                  = data.terraform_remote_state.vnet.outputs.resource_group_location
    resource_group_name       = data.terraform_remote_state.vnet.outputs.resource_group_name

    ip_configuration {
        name                          = "consulserverNicConfiguration"
        subnet_id                     = data.terraform_remote_state.vnet.outputs.shared_svcs_subnets[2]
        private_ip_address_allocation = "Dynamic"
    }

    tags = {
        environment = "Instruqt"
    }
}

resource "azurerm_lb" "consul" {
  name                = "consul-lb"
  location            = data.terraform_remote_state.vnet.outputs.resource_group_location
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name

  sku = "Standard"

  frontend_ip_configuration {
    name                 = "consulserverNicconfiguration"
    public_ip_address_id = azurerm_public_ip.consul.id
  }
}

resource "azurerm_lb_backend_address_pool" "consul" {
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id     = azurerm_lb.consul.id
  name                = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "consul" {
  network_interface_id    = azurerm_network_interface.consul.id
  ip_configuration_name   = "configuration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.consul.id
}

resource "azurerm_lb_probe" "consul" {
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id     = azurerm_lb.consul.id
  name                = "consul-http"
  port                = 8500
}

resource "azurerm_lb_rule" "consul" {
  resource_group_name            = data.terraform_remote_state.vnet.outputs.resource_group_name
  loadbalancer_id                = azurerm_lb.consul.id
  name                           = "consul"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 8500
  frontend_ip_configuration_name = "consulserverNicconfiguration"
  probe_id                       = azurerm_lb_probe.consul.id
  backend_address_pool_id        = azurerm_lb_backend_address_pool.consul.id
}


resource "azurerm_virtual_machine" "consul-server-vm" {
  name = "consul-server-vm"

  location            = data.terraform_remote_state.vnet.outputs.resource_group_location
  resource_group_name = data.terraform_remote_state.vnet.outputs.resource_group_name
  network_interface_ids = [azurerm_network_interface.consulserver-nic.id]
  vm_size               = "Standard_D1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "consulserverDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name = "consul-server-vm"
    admin_username       = "azure-user"
    custom_data          = base64encode(templatefile("./scripts/consul-server.sh", {}))
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/azure-user/.ssh/authorized_keys"
      key_data = var.ssh_public_key
    }

  }

}
