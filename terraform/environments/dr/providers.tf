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
  #   key    = "f5-ltm/dr/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ------------------------------------------------------------------------------
# Provider for DR ACTIVE device
# ------------------------------------------------------------------------------
provider "bigip" {
  alias    = "dr_active"
  address  = var.active_bigip_address
  username = var.bigip_username
  password = var.bigip_password
  port     = var.bigip_port
}

# ------------------------------------------------------------------------------
# Provider for DR STANDBY device
# ------------------------------------------------------------------------------
provider "bigip" {
  alias    = "dr_standby"
  address  = var.standby_bigip_address
  username = var.bigip_username
  password = var.bigip_password
  port     = var.bigip_port
}
