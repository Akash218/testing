terraform {
  required_version = ">= 1.3.0"

  required_providers {
    bigip = {
      source  = "F5Networks/bigip"
      version = ">= 1.22.0"
    }
  }

  # Uncomment and configure your backend:
  # backend "s3" {
  #   bucket = "your-tf-state-bucket"
  #   key    = "f5-ltm/dc/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ------------------------------------------------------------------------------
# Provider for DC ACTIVE device
# ------------------------------------------------------------------------------
provider "bigip" {
  alias    = "dc_active"
  address  = var.active_bigip_address
  username = var.bigip_username
  password = var.bigip_password
  port     = var.bigip_port
}

# ------------------------------------------------------------------------------
# Provider for DC STANDBY device
# ------------------------------------------------------------------------------
provider "bigip" {
  alias    = "dc_standby"
  address  = var.standby_bigip_address
  username = var.bigip_username
  password = var.bigip_password
  port     = var.bigip_port
}
