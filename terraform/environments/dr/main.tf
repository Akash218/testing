# ==============================================================================
# DR Environment — Main
#
# Bootstraps both DR Active and DR Standby devices using the f5-bootstrap module.
#
# EXECUTION ORDER:
#   1. Standby is bootstrapped FIRST (no DeviceTrust / DeviceGroup)
#   2. Active is bootstrapped SECOND (with DeviceTrust / DeviceGroup)
#      - depends_on ensures Standby is ready before Active establishes trust
#   3. DO on the Active device automatically:
#      - Establishes device trust with Standby
#      - Creates the sync-failover device group
#      - Performs initial config sync (Active → Standby)
# ==============================================================================

# ------------------------------------------------------------------------------
# Step 1: Bootstrap STANDBY device
#
# Configures: License, Hostname, DNS, NTP, Provisioning, VLANs, Self-IPs,
#             Routes, ConfigSync IP, Failover Address, Mirror IPs
# Does NOT configure: DeviceTrust, DeviceGroup (those come from Active)
# ------------------------------------------------------------------------------

module "dr_standby_bootstrap" {
  source = "../../modules/f5-bootstrap"

  providers = {
    bigip = bigip.dr_standby
  }

  # System
  hostname         = var.standby_hostname
  registration_key = var.standby_registration_key

  # DNS / NTP (shared settings)
  dns_nameservers    = var.dns_nameservers
  dns_search_domains = var.dns_search_domains
  ntp_servers        = var.ntp_servers
  timezone           = var.timezone

  # Provisioning
  provisioning = var.provisioning

  # Network
  vlans    = var.standby_vlans
  self_ips = var.standby_self_ips
  routes   = var.standby_routes

  # Users
  users = var.users

  # Syslog
  syslog_remote_servers = var.syslog_remote_servers

  # SNMP
  snmp_agent             = var.snmp_agent
  snmp_trap_destinations = var.snmp_trap_destinations

  # HA — Device connectivity (set on BOTH devices)
  configsync_ip            = var.standby_configsync_ip
  failover_unicast_address = var.standby_failover_unicast_address
  mirror_primary_ip        = var.standby_mirror_primary_ip
  mirror_secondary_ip      = var.standby_mirror_secondary_ip

  # HA — Peer config (NOT set on Standby)
  device_trust = null
  device_group = null
}

# ------------------------------------------------------------------------------
# Step 2: Bootstrap ACTIVE device
#
# Configures: Everything from Standby + DeviceTrust + DeviceGroup
# DO will automatically establish trust with Standby and sync config.
# ------------------------------------------------------------------------------

module "dr_active_bootstrap" {
  source = "../../modules/f5-bootstrap"

  providers = {
    bigip = bigip.dr_active
  }

  # Ensure Standby is fully configured before Active tries to establish trust
  depends_on = [module.dr_standby_bootstrap]

  # System
  hostname         = var.active_hostname
  registration_key = var.active_registration_key

  # DNS / NTP (shared settings)
  dns_nameservers    = var.dns_nameservers
  dns_search_domains = var.dns_search_domains
  ntp_servers        = var.ntp_servers
  timezone           = var.timezone

  # Provisioning
  provisioning = var.provisioning

  # Network
  vlans    = var.active_vlans
  self_ips = var.active_self_ips
  routes   = var.active_routes

  # Users
  users = var.users

  # Syslog
  syslog_remote_servers = var.syslog_remote_servers

  # SNMP
  snmp_agent             = var.snmp_agent
  snmp_trap_destinations = var.snmp_trap_destinations

  # HA — Device connectivity (set on BOTH devices)
  configsync_ip            = var.active_configsync_ip
  failover_unicast_address = var.active_failover_unicast_address
  mirror_primary_ip        = var.active_mirror_primary_ip
  mirror_secondary_ip      = var.active_mirror_secondary_ip

  # HA — Device Trust (ACTIVE only — reaches out to Standby)
  device_trust = {
    remote_host     = var.standby_bigip_address
    remote_username = var.bigip_username
    remote_password = var.bigip_password
    local_username  = var.bigip_username
    local_password  = var.bigip_password
  }

  # HA — Device Group (ACTIVE only — creates sync-failover group)
  device_group = {
    name    = var.device_group_name
    members = [var.active_hostname, var.standby_hostname]
    owner   = var.active_hostname
  }
}
